(* Four equal-capacity water-cooled chillers, each with dedicated pumps/valves.
   REFERENCE ONLY: create DDTs, DFBs and application variables in Control Expert.
   Split PROGRAM declarations/body into Data Editor + periodic MAST ST section.
   Map IO from/to field adapters BEFORE/AFTER this section respectively.
   ColdOrWarmStart must pulse for every PLC restart; see guide. *)
PROGRAM PRG_DC_Example
VAR
    ColdOrWarmStart : BOOL;
    FirstScan : BOOL;
    InitDone : BOOL;
    AutoEnable : BOOL;
    DisasterActive : BOOL;
    InfrastructureReady : BOOL;
    RecoveryAcknowledgement : BOOL;
    AlarmReset : BOOL;
    RotateCommand : BOOL;
    TemperatureQualityGood : BOOL;
    SupplyTemperature : REAL;
    IO : T_DC_IOArray;
    UnitStatus : T_DC_StatusArray;
    RunHours : T_DC_HoursArray;
    Requests : T_DC_BoolArray;
    Train01 : FB_DC_Train;
    Train02 : FB_DC_Train;
    Train03 : FB_DC_Train;
    Train04 : FB_DC_Train;
    Plant : FB_DC_Plant;
    DemandRegulator : FB_DC_Demand;
    ActualLoaded : INT;
    PlantStable : BOOL;
    i : INT;
END_VAR

FirstScan := ColdOrWarmStart OR NOT InitDone;
InitDone := TRUE;

Train01(FirstScan := FirstScan, RequestRun := Requests[1],
    RemoteAuto := IO[1].RemoteAuto,
    Maintenance := IO[1].Maintenance,
    RunPermit := IO[1].RunPermit,
    PowerAvailable := IO[1].PowerAvailable,
    HardTrip := IO[1].HardTrip,
    ChillerFault := IO[1].ChillerFault,
    WaterEquipmentFault := IO[1].WaterEquipmentFault,
    ValveOpenFb := IO[1].ValveOpenFb,
    ValveClosedFb := IO[1].ValveClosedFb,
    ChwPumpRunFb := IO[1].ChwPumpRunFb,
    CwPumpRunFb := IO[1].CwPumpRunFb,
    ChwFlowOk := IO[1].ChwFlowOk,
    CwFlowOk := IO[1].CwFlowOk,
    TowerReadyFb := IO[1].TowerReadyFb,
    ChillerRunFb := IO[1].ChillerRunFb,
    LoadedFb := IO[1].LoadedFb,
    LoadPermit := IO[1].LoadPermit,
    Reset := IO[1].Reset);
IO[1].OpenValvesCmd := Train01.OpenValves;
IO[1].RunChwPumpCmd := Train01.RunChwPump;
IO[1].RunCwPumpCmd := Train01.RunCwPump;
IO[1].RequestTowerCmd := Train01.RequestTower;
IO[1].RunChillerCmd := Train01.RunChiller;
IO[1].EnableLoadCmd := Train01.EnableLoad;
UnitStatus[1] := Train01.Status;

Train02(FirstScan := FirstScan, RequestRun := Requests[2],
    RemoteAuto := IO[2].RemoteAuto,
    Maintenance := IO[2].Maintenance,
    RunPermit := IO[2].RunPermit,
    PowerAvailable := IO[2].PowerAvailable,
    HardTrip := IO[2].HardTrip,
    ChillerFault := IO[2].ChillerFault,
    WaterEquipmentFault := IO[2].WaterEquipmentFault,
    ValveOpenFb := IO[2].ValveOpenFb,
    ValveClosedFb := IO[2].ValveClosedFb,
    ChwPumpRunFb := IO[2].ChwPumpRunFb,
    CwPumpRunFb := IO[2].CwPumpRunFb,
    ChwFlowOk := IO[2].ChwFlowOk,
    CwFlowOk := IO[2].CwFlowOk,
    TowerReadyFb := IO[2].TowerReadyFb,
    ChillerRunFb := IO[2].ChillerRunFb,
    LoadedFb := IO[2].LoadedFb,
    LoadPermit := IO[2].LoadPermit,
    Reset := IO[2].Reset);
IO[2].OpenValvesCmd := Train02.OpenValves;
IO[2].RunChwPumpCmd := Train02.RunChwPump;
IO[2].RunCwPumpCmd := Train02.RunCwPump;
IO[2].RequestTowerCmd := Train02.RequestTower;
IO[2].RunChillerCmd := Train02.RunChiller;
IO[2].EnableLoadCmd := Train02.EnableLoad;
UnitStatus[2] := Train02.Status;

Train03(FirstScan := FirstScan, RequestRun := Requests[3],
    RemoteAuto := IO[3].RemoteAuto,
    Maintenance := IO[3].Maintenance,
    RunPermit := IO[3].RunPermit,
    PowerAvailable := IO[3].PowerAvailable,
    HardTrip := IO[3].HardTrip,
    ChillerFault := IO[3].ChillerFault,
    WaterEquipmentFault := IO[3].WaterEquipmentFault,
    ValveOpenFb := IO[3].ValveOpenFb,
    ValveClosedFb := IO[3].ValveClosedFb,
    ChwPumpRunFb := IO[3].ChwPumpRunFb,
    CwPumpRunFb := IO[3].CwPumpRunFb,
    ChwFlowOk := IO[3].ChwFlowOk,
    CwFlowOk := IO[3].CwFlowOk,
    TowerReadyFb := IO[3].TowerReadyFb,
    ChillerRunFb := IO[3].ChillerRunFb,
    LoadedFb := IO[3].LoadedFb,
    LoadPermit := IO[3].LoadPermit,
    Reset := IO[3].Reset);
IO[3].OpenValvesCmd := Train03.OpenValves;
IO[3].RunChwPumpCmd := Train03.RunChwPump;
IO[3].RunCwPumpCmd := Train03.RunCwPump;
IO[3].RequestTowerCmd := Train03.RequestTower;
IO[3].RunChillerCmd := Train03.RunChiller;
IO[3].EnableLoadCmd := Train03.EnableLoad;
UnitStatus[3] := Train03.Status;

Train04(FirstScan := FirstScan, RequestRun := Requests[4],
    RemoteAuto := IO[4].RemoteAuto,
    Maintenance := IO[4].Maintenance,
    RunPermit := IO[4].RunPermit,
    PowerAvailable := IO[4].PowerAvailable,
    HardTrip := IO[4].HardTrip,
    ChillerFault := IO[4].ChillerFault,
    WaterEquipmentFault := IO[4].WaterEquipmentFault,
    ValveOpenFb := IO[4].ValveOpenFb,
    ValveClosedFb := IO[4].ValveClosedFb,
    ChwPumpRunFb := IO[4].ChwPumpRunFb,
    CwPumpRunFb := IO[4].CwPumpRunFb,
    ChwFlowOk := IO[4].ChwFlowOk,
    CwFlowOk := IO[4].CwFlowOk,
    TowerReadyFb := IO[4].TowerReadyFb,
    ChillerRunFb := IO[4].ChillerRunFb,
    LoadedFb := IO[4].LoadedFb,
    LoadPermit := IO[4].LoadPermit,
    Reset := IO[4].Reset);
IO[4].OpenValvesCmd := Train04.OpenValves;
IO[4].RunChwPumpCmd := Train04.RunChwPump;
IO[4].RunCwPumpCmd := Train04.RunCwPump;
IO[4].RequestTowerCmd := Train04.RequestTower;
IO[4].RunChillerCmd := Train04.RunChiller;
IO[4].EnableLoadCmd := Train04.EnableLoad;
UnitStatus[4] := Train04.Status;

ActualLoaded := 0;
PlantStable := NOT Plant.RecoveryHold AND NOT Plant.RotationActive;
FOR i := 1 TO 4 DO
    IF UnitStatus[i].Loaded THEN ActualLoaded := ActualLoaded + 1; END_IF;
    PlantStable := PlantStable AND NOT UnitStatus[i].Starting AND NOT UnitStatus[i].Stopping;
END_FOR;

DemandRegulator(
    FirstScan := FirstScan, Enable := AutoEnable,
    SensorValid := TemperatureQualityGood, SupplyTemperature := SupplyTemperature,
    LoadedCount := ActualLoaded, PlantStable := PlantStable,
    MinDuty := 1, MaxDuty := 3);

Plant(
    FirstScan := FirstScan, Enable := AutoEnable,
    DisasterActive := DisasterActive, InfrastructureReady := InfrastructureReady,
    AckRecovery := RecoveryAcknowledgement, AutoRecovery := FALSE,
    ResetAlarm := AlarmReset, DemandValid := DemandRegulator.DemandValid,
    Demand := DemandRegulator.Demand, UnitCount := 4, MaxDuty := 3, MaxParallel := 4,
    RotateEnable := TRUE, RotateNow := RotateCommand,
    Status := UnitStatus, RunHours := RunHours);
Requests := Plant.Request;

(* HMI: expose all UnitStatus fields, Plant outputs, Train unload/stop timeout
   alarms, and DemandRegulator.SensorAlarm / ConfigFault.
   IO is a software image: physical output writing and vendor protocol adapters
   belong to the application's single-authority I/O layer. *)
END_PROGRAM
