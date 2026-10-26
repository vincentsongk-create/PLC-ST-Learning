"""Execute the repository ST bodies with a host-only scan model, not a PLC.
Run: PYTHONPATH=/tmp/plc-st-validation python3 -m unittest discover \
     -s tests/datacenter_control_expert -v
"""
import unittest
from copy import deepcopy
from pathlib import Path
from blark.parse import parse_source_code
from st_scan import Block


def train():
    b = Block('02_FB_DC_Train.st')
    b.scan(FirstScan=True, RemoteAuto=True, RunPermit=True, PowerAvailable=True,
           ValveClosedFb=True,
           MinOff=2., MinOn=2., FlowStable=2., FlowTimeout=10., PostRun=3.,
           UnloadTimeout=3., StopTimeout=3., CapacityLossDelay=2.)
    b.v['FirstScan'] = False
    return b


def running_train():
    b = train()
    b.v.update(State=70, RequestRun=True, ChillerRunFb=True, LoadedFb=True,
               LoadPermit=True, ValveClosedFb=False, ValveOpenFb=True,
               ChwPumpRunFb=True, CwPumpRunFb=True, ChwFlowOk=True,
               CwFlowOk=True, TowerReadyFb=True)
    b.scan()
    return b


def plant():
    b = Block('03_FB_DC_Plant.st')
    for i in range(1, 5):
        b.v['Status'][i].update(Available=True, Ready=True)
        b.v['RunHours'][i] = float(i * 100)
    b.scan(FirstScan=True, Enable=True, InfrastructureReady=True, AutoRecovery=True,
           DemandValid=True, Demand=2, RecoveryStable=2., StartSpacing=3.,
           DemandUpDelay=1., DemandDownDelay=1., RotationOverlap=3.,
           RotationTimeout=30., RotationInterval=100.)
    b.v['FirstScan'] = False
    return b


def loaded(b, i):
    b.v['Status'][i].update(Ready=False, Loaded=True, ChillerRunning=True,
                            CanStop=True, Starting=False, Stopping=False)


class TrainTests(unittest.TestCase):
    def test_start_and_orderly_stop(self):
        b = train()
        b.scan(RequestRun=True)
        self.assertFalse(b.v['OpenValves'])
        b.scan(); b.scan()
        self.assertTrue(b.v['OpenValves'])
        self.assertFalse(b.v['RunChwPump'])
        b.scan(ValveOpenFb=True, ValveClosedFb=False)
        self.assertTrue(b.v['RunChwPump'])
        self.assertFalse(b.v['RunChiller'])
        b.scan(ChwPumpRunFb=True, CwPumpRunFb=True, ChwFlowOk=True, CwFlowOk=True)
        for _ in range(4): b.scan()
        self.assertTrue(b.v['RequestTower'])
        self.assertFalse(b.v['RunChiller'])
        b.scan(TowerReadyFb=True)
        self.assertTrue(b.v['RunChiller'])
        b.scan(ChillerRunFb=True, LoadPermit=True)
        b.scan(LoadedFb=True)
        self.assertTrue(b.v['Status']['Loaded'])
        for _ in range(3): b.scan()
        b.scan(RequestRun=False)
        self.assertEqual(b.v['State'], 80)
        self.assertFalse(b.v['EnableLoad'])
        self.assertTrue(b.v['RunChiller'])
        b.scan(LoadedFb=False)
        self.assertFalse(b.v['RunChiller'])
        self.assertTrue(b.v['RunChwPump'])
        b.scan(ChillerRunFb=False)
        for _ in range(4): b.scan()
        self.assertFalse(b.v['RunChwPump'])
        self.assertTrue(b.v['OpenValves'])
        b.scan(ChwPumpRunFb=False, CwPumpRunFb=False)
        self.assertFalse(b.v['OpenValves'])
        b.scan(ValveClosedFb=True, ValveOpenFb=False)
        self.assertEqual(b.v['State'], 0)

    def test_no_chiller_start_without_flow(self):
        b = train()
        b.v.update(State=50, RequestRun=True, ValveOpenFb=True, ValveClosedFb=False,
                   ChwPumpRunFb=True, CwPumpRunFb=True, TowerReadyFb=True)
        b.scan()
        self.assertFalse(b.v['RunChiller'])

    def test_flow_loss_shutdown_retains_water(self):
        b = running_train()
        for _ in range(4): b.scan(ChwFlowOk=False)
        self.assertTrue(b.v['Status']['Fault'])
        self.assertFalse(b.v['RunChiller'])
        self.assertTrue(b.v['RunChwPump'])
        self.assertTrue(b.v['OpenValves'])

    def test_stuck_stop_does_not_close_water(self):
        b = running_train()
        b.scan(ChillerFault=True)
        for _ in range(10): b.scan()
        self.assertEqual(b.v['State'], 90)
        self.assertTrue(b.v['StopTimedOut'])
        self.assertTrue(b.v['RunChwPump'])
        self.assertTrue(b.v['OpenValves'])

    def test_hard_trip_wins_over_start_and_reset(self):
        b = running_train()
        b.scan(HardTrip=True, Reset=True)
        for name in ('OpenValves', 'RunChwPump', 'RunCwPump', 'RequestTower',
                     'RunChiller', 'EnableLoad'):
            self.assertFalse(b.v[name], name)
        self.assertTrue(b.v['Status']['Fault'])

    def test_minimum_on_time(self):
        b = running_train()
        b.scan(RequestRun=False)
        self.assertEqual(b.v['State'], 70)
        b.scan(); b.scan()
        self.assertEqual(b.v['State'], 80)

    def test_fault_needs_reset_edge_at_rest(self):
        b = train()
        b.scan(HardTrip=True, Reset=True)
        b.scan(HardTrip=False)
        self.assertTrue(b.v['FaultLatched'])
        b.scan(Reset=False); b.scan(Reset=True)
        self.assertFalse(b.v['FaultLatched'])

    def test_reboot_preserves_healthy_loaded_chiller(self):
        b = running_train()
        b.scan(FirstScan=True, RequestRun=False)
        self.assertTrue(b.v['RunChiller'])
        self.assertTrue(b.v['EnableLoad'])

    def test_unexpected_restart_before_valve_closure_keeps_water(self):
        b = train()
        b.v.update(State=110, ValveOpenFb=True, ValveClosedFb=False)
        b.scan(ChillerRunFb=True)
        self.assertEqual(b.v['State'], 90)
        self.assertTrue(b.v['OpenValves'])
        self.assertTrue(b.v['RunChwPump'])
        self.assertFalse(b.v['RunChiller'])

    def test_expected_power_loss_does_not_latch_device_fault(self):
        b = running_train()
        b.scan(PowerAvailable=False, RunPermit=False)
        self.assertEqual(b.v['State'], 910)
        self.assertFalse(b.v['FaultLatched'])
        self.assertFalse(b.v['RunChiller'])
        b.scan(PowerAvailable=True, RunPermit=True, ChillerRunFb=False,
               LoadedFb=False, ChwPumpRunFb=False, CwPumpRunFb=False,
               ValveOpenFb=False, ValveClosedFb=True)
        self.assertEqual(b.v['State'], 0)
        self.assertFalse(b.v['FaultLatched'])


class PlantTests(unittest.TestCase):
    def test_recovery_and_repeated_start_spacing(self):
        b = plant()
        starts = []
        old = 0
        for tick in range(30):
            b.scan()
            count = sum(b.v['Request'].values())
            if count > old:
                starts.append(tick)
                for i in range(1, 5):
                    if b.v['Request'][i]: loaded(b, i)
            old = count
        self.assertEqual(sum(b.v['Request'].values()), 2)
        self.assertEqual(len(starts), 2)
        self.assertGreaterEqual(starts[1] - starts[0], 3)

    def test_failed_train_is_replaced_without_demand_debounce(self):
        b = plant()
        b.v.update(RecoveryHold=False, Target=2, DemandUpDelay=999., SpacingActive=False)
        b.v['Request'][1] = True; b.v['Request'][2] = True
        loaded(b, 1); loaded(b, 2)
        b.v['Status'][1].update(Available=False, Fault=True, Loaded=False,
                                ChillerRunning=False, Stopping=True)
        b.scan()
        self.assertFalse(b.v['Request'][1])
        self.assertTrue(b.v['Request'][3])

    def test_rotation_waits_for_continuous_replacement_capacity(self):
        b = plant()
        b.v.update(RecoveryHold=False, Target=1, Demand=1, SpacingActive=False)
        b.v['Request'][4] = True; loaded(b, 4)
        b.scan(RotateNow=True)
        self.assertTrue(b.v['Request'][1])
        for _ in range(6): b.scan(RotateNow=False)
        self.assertTrue(b.v['Request'][4])
        loaded(b, 1)
        b.scan(); b.scan()
        self.assertTrue(b.v['Request'][4])
        b.v['Status'][1]['Loaded'] = False
        b.scan()
        b.v['Status'][1]['Loaded'] = True
        for _ in range(3): b.scan()
        self.assertTrue(b.v['Request'][4])
        b.scan()
        self.assertFalse(b.v['Request'][4])

    def test_rotation_replacement_failure_keeps_original(self):
        b = plant()
        b.v.update(RecoveryHold=False, Target=1, Demand=1, SpacingActive=False)
        b.v['Request'][4] = True; loaded(b, 4)
        b.scan(RotateNow=True)
        b.v['Status'][1].update(Available=False, Fault=True)
        b.scan(RotateNow=False)
        self.assertTrue(b.v['Request'][4])
        self.assertTrue(b.v['RotationFailed'])

    def test_invalid_demand_cannot_shed(self):
        b = plant()
        b.v.update(RecoveryHold=False, Target=1, Demand=0, DemandValid=False)
        b.v['Request'][1] = True; loaded(b, 1)
        for _ in range(10): b.scan()
        self.assertTrue(b.v['Request'][1])
        self.assertEqual(b.v['Target'], 1)

    def test_sensor_failure_still_replaces_failed_unit_to_last_good_target(self):
        b = plant()
        b.v.update(RecoveryHold=False, Target=1, DemandValid=False, SpacingActive=False)
        b.v['Request'][1] = True
        b.v['Status'][1].update(Available=False, Ready=False, Fault=True)
        b.scan()
        self.assertTrue(b.v['Request'][2])
        self.assertEqual(b.v['Target'], 1)

    def test_manual_recovery_requires_ready_then_new_ack(self):
        b = plant()
        b.v['AutoRecovery'] = False
        for _ in range(10): b.scan()
        self.assertTrue(b.v['RecoveryHold'])
        b.scan(AckRecovery=True)
        self.assertFalse(b.v['RecoveryHold'])

    def test_reboot_adopts_running_units_without_target_zero_shed(self):
        b = plant()
        loaded(b, 1)
        b.scan(FirstScan=True)
        self.assertEqual(b.v['Target'], 1)
        self.assertTrue(b.v['Request'][1])

    def test_electrical_parallel_limit_blocks_rotation(self):
        b = plant()
        b.v.update(RecoveryHold=False, Target=3, Demand=3, MaxParallel=3,
                   SpacingActive=False)
        for i in (1, 2, 3):
            b.v['Request'][i] = True; loaded(b, i)
        b.scan(RotateNow=True)
        self.assertFalse(b.v['Request'][4])
        self.assertTrue(b.v['RotationBlocked'])


class DemandTests(unittest.TestCase):
    def test_high_temperature_stages_only_after_delay_and_settle(self):
        b = Block('04_FB_DC_Demand.st')
        b.scan(FirstScan=True, Enable=True, SensorValid=True, SupplyTemperature=9.,
               LoadedCount=1, PlantStable=True, SettleTime=2., AddDelay=2.)
        b.v['FirstScan'] = False
        for _ in range(6): b.scan()
        self.assertEqual(b.v['Demand'], 2)
        for _ in range(20): b.scan()
        self.assertEqual(b.v['Demand'], 2)  # No windup while new capacity is missing.

    def test_bad_temperature_freezes_demand(self):
        b = Block('04_FB_DC_Demand.st')
        b.scan(FirstScan=True, Enable=True, SensorValid=True, SupplyTemperature=7.)
        b.v.update(FirstScan=False, Demand=2)
        b.scan(SupplyTemperature=float('nan'))
        self.assertFalse(b.v['DemandValid'])
        self.assertEqual(b.v['Demand'], 2)


class IntegratedTests(unittest.TestCase):
    def test_four_train_load_shed_fault_replace_rotate_and_recover(self):
        p = plant()
        units = {i: train() for i in range(1, 5)}

        def step(**fleet_inputs):
            for i, u in units.items():
                # Ideal field equipment follows last scan's commands; genuine
                # timeout/missing-feedback cases are tested separately above.
                u.scan(RequestRun=p.v['Request'][i],
                       ValveOpenFb=u.v['OpenValves'], ValveClosedFb=not u.v['OpenValves'],
                       ChwPumpRunFb=u.v['RunChwPump'], CwPumpRunFb=u.v['RunCwPump'],
                       ChwFlowOk=u.v['RunChwPump'], CwFlowOk=u.v['RunCwPump'],
                       TowerReadyFb=u.v['RequestTower'], ChillerRunFb=u.v['RunChiller'],
                       LoadedFb=u.v['EnableLoad'], LoadPermit=True)
                p.v['Status'][i] = deepcopy(u.v['Status'])
            p.scan(**fleet_inputs)
            occupied = sum(bool(p.v['Request'][i] or units[i].v['ChillerRunFb'])
                           for i in units)
            self.assertLessEqual(occupied, p.v['MaxParallel'])

        for _ in range(120): step(Demand=3)
        self.assertEqual(p.v['LoadedCount'], 3)
        original = next(i for i in units if p.v['Request'][i])
        units[original].v['ChillerFault'] = True
        for _ in range(90): step()
        self.assertFalse(p.v['Request'][original])
        self.assertEqual(p.v['LoadedCount'], 3)
        units[original].v['ChillerFault'] = False
        units[original].v['Reset'] = True
        step()
        units[original].v['Reset'] = False
        self.assertFalse(units[original].v['FaultLatched'])
        before_rotation = dict(p.v['Request'])
        step(RotateNow=True)
        for _ in range(90): step(RotateNow=False)
        self.assertEqual(p.v['LoadedCount'], 3)
        self.assertNotEqual(before_rotation, p.v['Request'])
        self.assertFalse(p.v['RotationFailed'])
        for _ in range(90): step(Demand=1)
        self.assertEqual(p.v['LoadedCount'], 1)

        # Whole-plant outage; loss itself does not clear real equipment faults.
        for u in units.values():
            u.v.update(PowerAvailable=False, RunPermit=False)
        step(DisasterActive=True, InfrastructureReady=False)
        for _ in range(3): step()
        self.assertEqual(p.v['LoadedCount'], 0)
        for u in units.values():
            u.v.update(PowerAvailable=True, RunPermit=True)
        for _ in range(120):
            step(DisasterActive=False, InfrastructureReady=True, Demand=2)
        self.assertEqual(p.v['LoadedCount'], 2)
        self.assertTrue(all(not u.v['FaultLatched'] for u in units.values()))

    def test_all_reference_files_parse(self):
        root = Path(__file__).resolve().parents[2] / 'examples/datacenter_control_expert'
        files = sorted(root.glob('*.st'))
        self.assertEqual(len(files), 5)
        for source in files:
            with self.subTest(source=source.name):
                result = parse_source_code(source.read_text(), fn=source)
                self.assertIsNone(result.exception)


if __name__ == '__main__':
    unittest.main()
