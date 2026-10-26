(* Reference DFB: dedicated water equipment per chiller.
   Split declarations and body into a Control Expert DFB; see the Chinese guide.
   All commands are level signals; adapt to vendor start/stop interfaces separately. *)
FUNCTION_BLOCK FB_DC_Train
VAR_INPUT
    FirstScan : BOOL;
    RequestRun : BOOL;
    Reset : BOOL;
    RemoteAuto : BOOL;
    Maintenance : BOOL;
    RunPermit : BOOL;
    PowerAvailable : BOOL; (* Real per-train power feedback, distinct from process trips *)
    HardTrip : BOOL;
    ChillerFault : BOOL;
    WaterEquipmentFault : BOOL;
    ValveOpenFb : BOOL; (* Combined chilled/condenser valve open proof *)
    ValveClosedFb : BOOL;
    ChwPumpRunFb : BOOL;
    CwPumpRunFb : BOOL;
    ChwFlowOk : BOOL;
    CwFlowOk : BOOL;
    TowerReadyFb : BOOL; (* From tower controller; includes local fan staging *)
    ChillerRunFb : BOOL;
    LoadedFb : BOOL; (* Must be real ready/capacity feedback, not command echo *)
    LoadPermit : BOOL;
    MinOff : TIME := T#10m;
    MinOn : TIME := T#10m;
    ValveTimeout : TIME := T#60s;
    PumpTimeout : TIME := T#30s;
    FlowStable : TIME := T#15s;
    FlowTimeout : TIME := T#90s;
    FlowLossDelay : TIME := T#2s;
    CapacityLossDelay : TIME := T#10s;
    TowerTimeout : TIME := T#120s;
    ChillerTimeout : TIME := T#180s;
    LoadTimeout : TIME := T#180s;
    UnloadTimeout : TIME := T#120s;
    StopTimeout : TIME := T#180s;
    PostRun : TIME := T#180s;
END_VAR
VAR_OUTPUT
    OpenValves : BOOL;
    RunChwPump : BOOL;
    RunCwPump : BOOL;
    RequestTower : BOOL;
    RunChiller : BOOL;
    EnableLoad : BOOL;
    Status : T_DC_TrainStatus;
    UnloadTimedOut : BOOL;
    StopTimedOut : BOOL;
END_VAR
VAR
    State : INT;
    FaultLatched : BOOL;
    FaultCode : INT;
    OldReset : BOOL;
    ResetEdge : BOOL;
    WaterOk : BOOL;
    ConfigOk : BOOL;
    ControlledTrip : BOOL;
    tmOff : TON;
    tmOn : TON;
    tmValveOpen : TON;
    tmPump : TON;
    tmFlowStable : TON;
    tmFlowWait : TON;
    tmFlowLoss : TON;
    tmCapacityLoss : TON;
    tmTower : TON;
    tmChiller : TON;
    tmLoad : TON;
    tmUnload : TON;
    tmStop : TON;
    tmPost : TON;
    tmPumpStop : TON;
    tmValveClose : TON;
END_VAR

ResetEdge := Reset AND NOT OldReset;
OldReset := Reset;
ConfigOk := (MinOff > T#0s) AND (MinOn > T#0s)
    AND (ValveTimeout > T#0s) AND (PumpTimeout > T#0s)
    AND (FlowStable > T#0s) AND (FlowTimeout > FlowStable)
    AND (FlowLossDelay >= T#0s) AND (CapacityLossDelay > T#0s)
    AND (TowerTimeout > T#0s)
    AND (ChillerTimeout > T#0s) AND (LoadTimeout > T#0s)
    AND (UnloadTimeout > T#0s) AND (StopTimeout > T#0s)
    AND (PostRun > T#0s);
WaterOk := ValveOpenFb AND ChwPumpRunFb AND CwPumpRunFb
    AND ChwFlowOk AND CwFlowOk;

(* Non-retained state is reconstructed from real feedback, never retained commands. *)
IF FirstScan THEN
    OldReset := Reset;
    ResetEdge := FALSE;
    State := 0;
    FaultLatched := FALSE;
    FaultCode := 0;
    UnloadTimedOut := FALSE;
    StopTimedOut := FALSE;
    IF ChillerRunFb THEN
        IF LoadedFb THEN State := 70; ELSE State := 60; END_IF;
    ELSIF ChwPumpRunFb OR CwPumpRunFb THEN
        State := 100;
    ELSIF ValveOpenFb THEN
        State := 120;
    END_IF;
END_IF;

(* Call EVERY timer exactly once per scan, even while idle or faulted. *)
tmOff(IN := NOT ChillerRunFb AND NOT FirstScan, PT := MinOff);
tmOn(IN := ChillerRunFb AND NOT FirstScan, PT := MinOn);
tmValveOpen(IN := (State = 10) AND NOT FirstScan, PT := ValveTimeout);
tmPump(IN := (State = 20) AND NOT FirstScan, PT := PumpTimeout);
tmFlowStable(IN := WaterOk AND NOT FirstScan, PT := FlowStable);
tmFlowWait(IN := (State = 30) AND NOT FirstScan, PT := FlowTimeout);
tmFlowLoss(IN := (State >= 50) AND (State <= 80) AND NOT WaterOk
    AND NOT FirstScan, PT := FlowLossDelay);
tmCapacityLoss(IN := (State = 70) AND NOT LoadedFb AND NOT FirstScan,
    PT := CapacityLossDelay);
tmTower(IN := (State = 40) AND NOT FirstScan, PT := TowerTimeout);
tmChiller(IN := (State = 50) AND NOT FirstScan, PT := ChillerTimeout);
tmLoad(IN := (State = 60) AND NOT FirstScan, PT := LoadTimeout);
tmUnload(IN := (State = 80) AND NOT FirstScan, PT := UnloadTimeout);
tmStop(IN := (State = 90) AND NOT FirstScan, PT := StopTimeout);
tmPost(IN := (State = 100) AND NOT FirstScan, PT := PostRun);
tmPumpStop(IN := (State = 110) AND NOT FirstScan, PT := PumpTimeout);
tmValveClose(IN := (State = 120) AND NOT FirstScan, PT := ValveTimeout);

IF ResetEdge AND NOT ChillerRunFb AND NOT ChwPumpRunFb AND NOT CwPumpRunFb
    AND ValveClosedFb AND NOT ValveOpenFb AND NOT LoadedFb
    AND NOT ChillerFault AND NOT WaterEquipmentFault AND RunPermit
    AND NOT HardTrip AND RemoteAuto AND PowerAvailable AND ConfigOk
    AND ((State = 0) OR (State = 900)) THEN
    FaultLatched := FALSE;
    FaultCode := 0;
    UnloadTimedOut := FALSE;
    StopTimedOut := FALSE;
    State := 0;
END_IF;

ControlledTrip := FALSE;
IF NOT ConfigOk THEN FaultCode := 1; ControlledTrip := TRUE;
ELSIF NOT RunPermit AND (((State > 0) AND (State < 90)) OR ChillerRunFb) THEN
    FaultCode := 2; ControlledTrip := TRUE;
ELSIF ChillerFault THEN FaultCode := 3; ControlledTrip := TRUE;
ELSIF WaterEquipmentFault THEN FaultCode := 4; ControlledTrip := TRUE;
ELSIF (State >= 50) AND (State <= 80) AND NOT ValveOpenFb THEN
    FaultCode := 5; ControlledTrip := TRUE;
ELSIF tmFlowLoss.Q THEN FaultCode := 6; ControlledTrip := TRUE;
ELSIF (State >= 50) AND (State <= 80) AND NOT TowerReadyFb THEN
    FaultCode := 7; ControlledTrip := TRUE;
ELSIF ((State = 60) OR (State = 70) OR (State = 80)) AND NOT ChillerRunFb THEN
    FaultCode := 8; ControlledTrip := TRUE;
ELSIF tmCapacityLoss.Q THEN
    FaultCode := 9; ControlledTrip := TRUE;
ELSIF LoadedFb AND NOT ChillerRunFb THEN
    FaultCode := 10; ControlledTrip := TRUE;
ELSIF ValveOpenFb AND ValveClosedFb THEN
    FaultCode := 11; ControlledTrip := TRUE;
ELSIF ChillerRunFb AND ((State < 50) OR ((State >= 100) AND (State <= 120))
    OR (State = 900)) THEN
    FaultCode := 14; ControlledTrip := TRUE;
END_IF;

(* Hardwired safeties remain independent. A hard trip removes ALL commands. *)
IF HardTrip THEN
    FaultLatched := TRUE;
    FaultCode := 12;
    State := 900;
ELSIF NOT RemoteAuto THEN
    IF ChillerRunFb OR ChwPumpRunFb OR CwPumpRunFb
        OR ((State > 0) AND (State < 900)) THEN
        FaultLatched := TRUE; FaultCode := 13;
    END_IF;
    IF FaultLatched THEN State := 900; ELSE State := 0; END_IF;
ELSIF NOT PowerAvailable THEN
    (* Expected loss of supply is not a device-fault latch. Existing faults persist. *)
    State := 910;
ELSIF ControlledTrip THEN
    FaultLatched := TRUE;
    IF ChillerRunFb AND (State >= 100) THEN
        State := 90;
    ELSIF (State < 90) OR (State = 900) THEN
        IF ChillerRunFb THEN State := 90;
        ELSIF ChwPumpRunFb OR CwPumpRunFb THEN State := 100;
        ELSIF NOT ValveClosedFb THEN State := 120;
        ELSE State := 900;
        END_IF;
    END_IF;
END_IF;

(* Normal request withdrawal honors MinOn. Startup cancellation needs no MinOn. *)
IF NOT FirstScan AND NOT RequestRun AND NOT ControlledTrip AND NOT HardTrip
    AND RemoteAuto AND PowerAvailable AND (State > 0) AND (State < 80) THEN
    IF (State = 70) AND tmOn.Q THEN State := 80;
    ELSIF State = 10 THEN State := 120;
    ELSIF (State >= 20) AND (State <= 40) THEN State := 100;
    ELSIF (State = 50) OR (State = 60) THEN
        IF ChillerRunFb THEN State := 80; ELSE State := 100; END_IF;
    END_IF;
END_IF;

IF NOT HardTrip AND RemoteAuto AND PowerAvailable THEN
    CASE State OF
    0:
        IF ChillerRunFb OR ChwPumpRunFb OR CwPumpRunFb OR LoadedFb THEN
            FaultLatched := TRUE; FaultCode := 14;
            IF ChillerRunFb THEN State := 90; ELSE State := 100; END_IF;
        ELSIF RequestRun AND NOT FaultLatched AND NOT Maintenance
            AND RunPermit AND ConfigOk AND tmOff.Q AND ValveClosedFb THEN
            State := 10;
        END_IF;
    10:
        IF ValveOpenFb AND NOT ValveClosedFb THEN State := 20;
        ELSIF tmValveOpen.Q THEN FaultLatched := TRUE; FaultCode := 20; State := 120;
        END_IF;
    20:
        IF ChwPumpRunFb AND CwPumpRunFb THEN State := 30;
        ELSIF tmPump.Q THEN FaultLatched := TRUE; FaultCode := 21; State := 100;
        END_IF;
    30:
        IF tmFlowStable.Q THEN State := 40;
        ELSIF tmFlowWait.Q THEN FaultLatched := TRUE; FaultCode := 22; State := 100;
        END_IF;
    40:
        IF TowerReadyFb AND tmFlowStable.Q THEN State := 50;
        ELSIF tmTower.Q THEN FaultLatched := TRUE; FaultCode := 23; State := 100;
        END_IF;
    50:
        IF ChillerRunFb THEN State := 60;
        ELSIF tmChiller.Q THEN FaultLatched := TRUE; FaultCode := 24; State := 90;
        END_IF;
    60:
        IF LoadedFb AND LoadPermit AND tmFlowStable.Q THEN State := 70;
        ELSIF tmLoad.Q THEN FaultLatched := TRUE; FaultCode := 25; State := 80;
        END_IF;
    70:
        (* Loss of load permission unloads through the normal stop path. *)
        IF NOT LoadPermit THEN
            FaultLatched := TRUE; FaultCode := 26; State := 80;
        END_IF;
    80:
        IF NOT LoadedFb THEN State := 90;
        ELSIF tmUnload.Q THEN
            UnloadTimedOut := TRUE; FaultLatched := TRUE; FaultCode := 27; State := 90;
        END_IF;
    90:
        (* A stuck run feedback MUST NOT be treated as a stopped chiller. *)
        IF NOT ChillerRunFb THEN State := 100;
        ELSIF tmStop.Q THEN
            StopTimedOut := TRUE; FaultLatched := TRUE; FaultCode := 28;
        END_IF;
    100:
        IF ChillerRunFb THEN
            FaultLatched := TRUE; FaultCode := 29; State := 90;
        ELSIF tmPost.Q THEN State := 110;
        END_IF;
    110:
        IF NOT ChwPumpRunFb AND NOT CwPumpRunFb THEN State := 120;
        ELSIF tmPumpStop.Q THEN
            FaultLatched := TRUE; FaultCode := 30;
            (* Keep valves open until BOTH pumps really stop. *)
        END_IF;
    120:
        IF ChillerRunFb OR ChwPumpRunFb OR CwPumpRunFb THEN
            FaultLatched := TRUE; FaultCode := 31;
            IF ChillerRunFb THEN State := 90; ELSE State := 110; END_IF;
        ELSIF ValveClosedFb AND NOT ValveOpenFb THEN
            IF FaultLatched THEN State := 900; ELSE State := 0; END_IF;
        ELSIF tmValveClose.Q THEN
            FaultLatched := TRUE; FaultCode := 32;
        END_IF;
    900:
        (* No automatic reset/retry. A real reset edge at a safe rest is required. *)
        IF ChillerRunFb THEN State := 90;
        ELSIF ChwPumpRunFb OR CwPumpRunFb THEN State := 100;
        END_IF;
    910:
        (* Re-establish a safe rest before allowing the fleet to restart this train. *)
        IF ChillerRunFb THEN State := 90;
        ELSIF ChwPumpRunFb OR CwPumpRunFb THEN State := 100;
        ELSIF NOT ValveClosedFb THEN State := 120;
        ELSIF FaultLatched THEN State := 900;
        ELSE State := 0;
        END_IF;
    ELSE
        FaultLatched := TRUE; FaultCode := 99;
        IF ChillerRunFb THEN State := 90; ELSE State := 100; END_IF;
    END_CASE;
END_IF;

OpenValves := (State >= 10) AND (State <= 110);
RunChwPump := (State >= 20) AND (State <= 100);
RunCwPump := RunChwPump;
RequestTower := (State >= 40) AND (State <= 100);
RunChiller := (State >= 50) AND (State <= 80);
EnableLoad := (((State = 60) AND tmFlowStable.Q) OR ((State = 70) AND WaterOk))
    AND LoadPermit AND TowerReadyFb AND ChillerRunFb AND NOT FaultLatched;
(* Physical interlocks cut chiller/load immediately; water may continue for post-run. *)
RunChiller := RunChiller AND RunPermit AND NOT ChillerFault
    AND NOT WaterEquipmentFault AND ValveOpenFb AND NOT tmFlowLoss.Q
    AND TowerReadyFb AND ConfigOk AND ((State <> 50) OR WaterOk);
IF HardTrip OR NOT RemoteAuto OR NOT PowerAvailable THEN
    OpenValves := FALSE; RunChwPump := FALSE; RunCwPump := FALSE;
    RequestTower := FALSE; RunChiller := FALSE; EnableLoad := FALSE;
END_IF;
EnableLoad := EnableLoad AND RunChiller;
Status.Available := RemoteAuto AND NOT Maintenance AND RunPermit
    AND PowerAvailable
    AND NOT HardTrip AND NOT ChillerFault AND NOT WaterEquipmentFault
    AND NOT FaultLatched AND ConfigOk;
Status.Ready := Status.Available AND (State = 0) AND tmOff.Q
    AND ValveClosedFb AND NOT ValveOpenFb AND NOT ChillerRunFb
    AND NOT ChwPumpRunFb AND NOT CwPumpRunFb AND NOT LoadedFb;
Status.Loaded := (State = 70) AND LoadedFb AND ChillerRunFb AND WaterOk
    AND TowerReadyFb AND LoadPermit AND NOT FaultLatched
    AND RemoteAuto AND RunPermit AND NOT HardTrip;
Status.ChillerRunning := ChillerRunFb;
Status.Starting := (State >= 10) AND (State <= 60);
Status.Stopping := (State >= 80) AND (State <= 120);
Status.CanStop := (State = 70) AND tmOn.Q;
Status.Fault := FaultLatched;
Status.State := State;
Status.FaultCode := FaultCode;
END_FUNCTION_BLOCK
