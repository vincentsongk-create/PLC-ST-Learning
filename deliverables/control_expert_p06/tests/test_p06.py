import unittest
import zipfile
import json
from pathlib import Path
from copy import deepcopy
import xml.etree.ElementTree as ET
from scan_host import Host

BASE = Path(__file__).resolve().parents[1]


def unit(state=0):
    h = Host('CHP01', ['Chiller_Start', 'Chiller_Stop', 'OUT_ARB', 'P06_FINAL_GUARD'])
    h.v.update(P06_State=state, CH_INFL_MIN=50., CHV_OSTP=70., STOP_PUMP_DELAY=120,
               START_LOWFL_TM=120, ACH_PWR=True, ACH_AM=True, CHP_REM=True,
               CHV01_FB=100., CHV02_FB=100., CHV03_FB=100., CHP_MIN=30.,
               TST_CAP_STP=85., TST_CAP=90., ACH_EN=state==40,
               ACH_RUN=state==40, CHP_RUN=state==40, CHS_FL01=100. if state==40 else 0.,
               ACH_STC=True, CHP_STC=True)
    return h


def fleet():
    h = Host('SMCL', ['S30_STAGE'])
    h.v.update(N_CH_CFG=5, ACH_MinQ=2, STG_INTERVAL=600, HANDOVER_TM=3,
               RCV_TM=30, CH_NOM_KW=1661., CH_NOM_FL=124., COMM_TMO=10,
               System_ENA=True, STAGE_REQ=2, CHS_TSP_OUT=17., HANDOVER_DT=1.1,
               ROT_DAY=1, ROT_HHMM=1500)
    for i in range(1,6):
        for n,val in dict(P06_Version=2606,P06_Ext=2,HB_CNT=0,HB_LAST=1,
                          RCV_HB0=0,UNIT_EN=True,CH_PWR=True,STOP_DONE=True,
                          COMM_OK=True,CH_RUNH=float(i*100),CH_STS_CHST=17.).items():
            h.v[n][i]=val
    return h


def loaded(h,i):
    for n,value in dict(ACH_S=True,CHWP_S=True,START_DONE=True,STOP_DONE=False,P06_Ext=12,ACH_ENA_FB=True).items():
        h.v[n][i]=value


class Unit(unittest.TestCase):
    def test_flow_loss_cuts_physical_chiller_output(self):
        h=unit(40)
        h.scan(CHS_FL01=0.)
        self.assertFalse(h.v['ACH_STC'])
        self.assertTrue(h.v['CHP_Auto_OP'])
        for _ in range(3):h.scan()
        self.assertTrue(h.v['P06_SeqFault'])
        self.assertEqual(h.v['P06_State'],50)

    def test_maintenance_holds_valves_until_actual_stop_and_postrun(self):
        h=unit(40)
        h.v.update(CHV01_Auto_OP=100.,CHV02_Auto_OP=100.,CHV03_Auto_OP=0.)
        h.scan(CH_MS=True)
        self.assertEqual(h.v['P06_State'],50)
        self.assertFalse(h.v['P06_Isolatable'])
        self.assertEqual(h.v['CHV01_Auto_OP'],100.)
        self.assertTrue(h.v['CHP_Auto_OP'])
        h.scan(ACH_RUN=False)
        for _ in range(123):h.scan()
        self.assertEqual(h.v['P06_State'],70)
        self.assertEqual(h.v['CHV01_Auto_OP'],100.)
        h.scan(CHP_RUN=False)
        h.scan()
        self.assertTrue(h.v['P06_Isolatable'])
        self.assertEqual(h.v['CHV01_Auto_OP'],0.)

    def test_low_flow_start_fails_independently_of_supply_temperature(self):
        h=unit(20)
        h.scan(ACH_EN=True,CHP_RUN=True,CHS_FL01=0.)
        for _ in range(121):h.scan()
        self.assertTrue(h.v['P06_SeqFault'])
        self.assertEqual(h.v['P06_FaultCode'],20)
        self.assertFalse(h.v['START_ACH_REQ'])

    def test_chiller_refusal_has_independent_timeout(self):
        h=unit(30)
        h.scan(ACH_EN=True,CHP_RUN=True,CHS_FL01=100.,CHS_T01=17.,CHS_T02=17.)
        for _ in range(181):h.scan()
        self.assertTrue(h.v['P06_SeqFault'])
        self.assertEqual(h.v['P06_FaultCode'],30)

    def test_stuck_chiller_never_advances_to_stop_pump(self):
        # Feed an actually running chiller so the state must remain at 50.
        h=unit(50);h.v.update(ACH_RUN=True,CHP_RUN=True,CHS_FL01=100.)
        for _ in range(190):h.scan()
        self.assertEqual(h.v['P06_State'],50)
        self.assertTrue(h.v['P06_StopFault'])
        self.assertTrue(h.v['CHP_Auto_OP'])

    def test_reenable_cannot_reverse_incomplete_stop(self):
        h=unit(50);h.v.update(ACH_RUN=True,CHP_RUN=True,CHS_FL01=100.)
        h.scan(ACH_EN=True)
        self.assertEqual(h.v['P06_State'],50)
        self.assertFalse(h.v['START_ACH_REQ'])

    def test_flow_bad_quality_cannot_use_held_good_value(self):
        h=unit(40)
        h.scan(CHS_FL01_UnderRange=True,CHS_FL01=100.)
        self.assertFalse(h.v['ACH_STC'])

    def test_minimum_off_time_is_enforced(self):
        h=unit()
        h.scan(P06_Boot=True,ACH_EN=True)
        h.scan(P06_Boot=False)
        self.assertEqual(h.v['P06_State'],0)
        for _ in range(601):h.scan()
        self.assertNotEqual(h.v['P06_State'],0)

    def test_quick_restart_option_is_explicit_and_does_not_clear_faults(self):
        h=unit(40)
        h.scan(ACH_PWR=False,P06_FastRestartApproved=True)
        self.assertTrue(h.v['P06_PowerEvent'])
        self.assertEqual(h.v['P06_OffPreset'],120.)
        h.scan(ACH_PWR=True,ACH_RUN=False,CHP_RUN=False)
        h.scan();h.scan()
        h.v['P06_SeqFault']=True
        for _ in range(130):h.scan()
        self.assertNotIn(h.v['P06_State'],(10,20,30,40))
        self.assertTrue(h.v['P06_SeqFault'])

    def test_illegal_state_is_a_fault(self):
        h=unit(1234)
        h.scan()
        self.assertTrue(h.v['P06_SeqFault'])
        self.assertEqual(h.v['P06_FaultCode'],99)
        self.assertFalse(h.v['START_ACH_REQ'])

    def test_useful_tes_discharge_is_held_until_handover(self):
        h=unit(60)
        h.v.update(ACH_EN=True,CHP_RUN=True,CHS_FL01=100.,TST_MODE=3,TST_CAP=90.,TST_CAP_MINSTP=20.)
        for _ in range(180):h.scan()
        self.assertEqual(h.v['P06_State'],60)
        self.assertTrue(h.v['CHP_Auto_OP'])
        h.scan(ACH_EN=False)
        self.assertEqual(h.v['P06_State'],70)
        self.assertFalse(h.v['CHP_Auto_OP'])


class Fleet(unittest.TestCase):
    def test_one_start_is_in_flight(self):
        h=fleet()
        for _ in range(20):h.scan()
        self.assertEqual(sum(h.v['CH_ENA'].values()),1)
        self.assertNotEqual(h.v['P06_StartID'],0)

    def test_disable_cancels_pending_start_into_orderly_stop(self):
        h=fleet();h.scan()
        unit_id=h.v['P06_StartID']
        h.v['STOP_DONE'][unit_id]=False
        h.scan(System_ENA=False)
        self.assertFalse(h.v['CH_ENA'][unit_id])
        self.assertEqual(h.v['P06_StartID'],0)
        self.assertEqual(h.v['P06_StopID'],unit_id)

    def test_spacing_and_timer_reset_between_transactions(self):
        h=fleet();h.scan()
        first=h.v['P06_StartID'];self.assertGreater(first,0)
        loaded(h,first)
        for _ in range(50):h.scan()
        self.assertEqual(sum(h.v['CH_ENA'].values()),1)
        for _ in range(75):h.scan()
        self.assertEqual(sum(h.v['CH_ENA'].values()),2)
        self.assertFalse(h.v['P06_StartAlarm'])
        second=h.v['P06_StartID']
        self.assertNotEqual(second,first)
        h.scan()
        self.assertLess(h.v['P06_TStart']['ET'],10.)

    def test_unknown_peer_is_never_forced_off_after_recovery_timeout(self):
        h=fleet()
        h.v.update(RCV_ACT=True,RCV_CNT=30)
        h.v['P06_Version'][5]=0
        h.v['CH_ENA'][5]=True
        h.scan()
        self.assertFalse(h.v['P06_Known'][5])
        self.assertTrue(h.v['CH_ENA'][5])
        self.assertTrue(h.v['P06_UnknownAlarm'])

    def test_late_peer_echo_is_adopted_before_dispatch(self):
        h=fleet()
        h.v['ACH_ENA_FB'][3]=True
        loaded(h,3)
        h.scan()
        self.assertTrue(h.v['P06_Known'][3])
        self.assertTrue(h.v['CH_ENA'][3])

    def test_legacy_protocol_is_not_selected(self):
        h=fleet()
        for i in range(1,6):h.v['P06_Version'][i]=0
        for _ in range(10):h.scan()
        self.assertFalse(any(h.v['CH_ENA'].values()))

    def test_rotation_waits_for_continuous_valid_capacity(self):
        h=fleet();h.v.update(STAGE_REQ=2,P06_RotatePending=True)
        for i in (4,5):h.v['CH_ENA'][i]=True;loaded(h,i)
        h.scan()
        old,new=h.v['P06_RotOld'],h.v['P06_RotNew']
        self.assertGreater(old,0);self.assertGreater(new,0)
        for _ in range(5):h.scan()
        self.assertTrue(h.v['CH_ENA'][old])
        loaded(h,new)
        h.v['CH_STS_CHST'][new]=22.
        for _ in range(5):h.scan()
        self.assertTrue(h.v['CH_ENA'][old])
        h.v['CH_STS_CHST'][new]=17.
        h.scan();h.scan()
        h.v['P06_Ext'][new]=4 # Temperature quality loss restarts overlap.
        h.scan();h.v['P06_Ext'][new]=12
        for _ in range(3):h.scan()
        self.assertTrue(h.v['CH_ENA'][old])
        h.scan()
        self.assertFalse(h.v['CH_ENA'][old])

    def test_replacement_fault_keeps_original(self):
        h=fleet();h.v.update(STAGE_REQ=2,P06_RotatePending=True)
        for i in (4,5):h.v['CH_ENA'][i]=True;loaded(h,i)
        h.scan()
        old,new=h.v['P06_RotOld'],h.v['P06_RotNew']
        h.v['UNIT_EN'][new]=False
        h.scan()
        self.assertTrue(h.v['CH_ENA'][old])
        self.assertFalse(h.v['CH_ENA'][new])

    def test_old_unit_fault_keeps_replacement(self):
        h=fleet();h.v.update(STAGE_REQ=2,P06_RotatePending=True)
        for i in (4,5):h.v['CH_ENA'][i]=True;loaded(h,i)
        h.scan()
        old,new=h.v['P06_RotOld'],h.v['P06_RotNew']
        h.v['UNIT_EN'][old]=False
        h.scan()
        self.assertTrue(h.v['CH_ENA'][new])
        self.assertEqual(h.v['P06_RotOld'],0)

    def test_cross_pair_flow_selection(self):
        h=Host('SMCL',['S20_CALC'])
        h.scan(OK_CHWR_FL01=True,OK_CHWS_FL02=True,V_CHWR_FL01=100.,V_CHWS_FL02=200.,
               POLL_TM=600,CH_NOM_FL=124.)
        self.assertEqual(h.v['FLOW_A'],100.)
        self.assertEqual(h.v['FLOW_B'],200.)
        self.assertFalse(h.v['P06_LoadValid']) # Temperature quality missing.


class NativePackage(unittest.TestCase):
    def test_archives_and_unbuilt_marker(self):
        for name in ('CHP01-P06.ZEF','SMCL-P06.ZEF'):
            with zipfile.ZipFile(BASE/name) as z:
                self.assertIsNone(z.testzip())
                self.assertEqual(ET.fromstring(z.read('props.xml')).findtext('AppBuilt'),'FALSE')
                root=ET.fromstring(z.read('unitpro.xef'))
                names=[v.get('name') for v in root.findall('./dataBlock/variables')]
                self.assertEqual(len(names),len(set(names)))
                orders=[int(p.find('identProgram').get('SectionOrder')) for p in root.findall('program')
                        if p.find('identProgram').get('type')=='section']
                self.assertEqual(sorted(orders),list(range(1,len(orders)+1)))


if __name__=='__main__':unittest.main()
