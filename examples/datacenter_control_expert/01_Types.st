(* IEC reference declarations. Create these DDTs in Control Expert's Data Editor.
   This file is NOT an XDB/XEF import file. Indices are always 1..16. *)
TYPE T_DC_TrainStatus :
STRUCT
    Available : BOOL;
    Ready : BOOL;
    Loaded : BOOL;
    ChillerRunning : BOOL;
    Starting : BOOL;
    Stopping : BOOL;
    CanStop : BOOL;
    Fault : BOOL;
    State : INT;
    FaultCode : INT;
END_STRUCT
END_TYPE

TYPE T_DC_StatusArray : ARRAY [1..16] OF T_DC_TrainStatus; END_TYPE
TYPE T_DC_BoolArray : ARRAY [1..16] OF BOOL; END_TYPE
TYPE T_DC_HoursArray : ARRAY [1..16] OF REAL; END_TYPE

TYPE T_DC_TrainIO :
STRUCT
    RemoteAuto : BOOL;
    Maintenance : BOOL;
    RunPermit : BOOL;
    PowerAvailable : BOOL;
    HardTrip : BOOL;
    ChillerFault : BOOL;
    WaterEquipmentFault : BOOL;
    ValveOpenFb : BOOL;
    ValveClosedFb : BOOL;
    ChwPumpRunFb : BOOL;
    CwPumpRunFb : BOOL;
    ChwFlowOk : BOOL;
    CwFlowOk : BOOL;
    TowerReadyFb : BOOL;
    ChillerRunFb : BOOL;
    LoadedFb : BOOL;
    LoadPermit : BOOL;
    Reset : BOOL;
    OpenValvesCmd : BOOL;
    RunChwPumpCmd : BOOL;
    RunCwPumpCmd : BOOL;
    RequestTowerCmd : BOOL;
    RunChillerCmd : BOOL;
    EnableLoadCmd : BOOL;
END_STRUCT
END_TYPE
TYPE T_DC_IOArray : ARRAY [1..16] OF T_DC_TrainIO; END_TYPE
