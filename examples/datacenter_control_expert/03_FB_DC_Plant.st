(* Fleet dispatch. Equal-capacity chillers; maximum 16.
   Call all Train DFBs BEFORE this DFB; requests take effect next PLC scan. *)
FUNCTION_BLOCK FB_DC_Plant
VAR_INPUT
    FirstScan : BOOL;
    Enable : BOOL;
    DisasterActive : BOOL; (* Recovery latch input, NOT a safety output *)
    InfrastructureReady : BOOL; (* Power, BMS authority, common water system ready *)
    AckRecovery : BOOL;
    AutoRecovery : BOOL := FALSE;
    ResetAlarm : BOOL;
    DemandValid : BOOL;
    Demand : INT; (* Desired duty count from BMS or validated demand regulator *)
    UnitCount : INT := 4;
    MaxDuty : INT := 3; (* N+1 reserve with four installed units *)
    MaxParallel : INT := 4; (* Electrical/hydraulic limit, includes rotation overlap *)
    RotateEnable : BOOL := TRUE;
    RotateNow : BOOL;
    Status : T_DC_StatusArray;
    RunHours : T_DC_HoursArray; (* External, validated RETAIN hour meters *)
    RecoveryStable : TIME := T#60s;
    StartSpacing : TIME := T#120s;
    DemandUpDelay : TIME := T#60s;
    DemandDownDelay : TIME := T#300s;
    RotationInterval : TIME := T#168h;
    RotationOverlap : TIME := T#60s;
    RotationTimeout : TIME := T#30m;
END_VAR
VAR_OUTPUT
    Request : T_DC_BoolArray;
    RecoveryHold : BOOL;
    Target : INT;
    RunningCount : INT;
    LoadedCount : INT;
    RequestedCount : INT;
    CapacityShortage : BOOL;
    NoStartCandidate : BOOL;
    ReserveUnavailable : BOOL;
    ConfigFault : BOOL;
    RotationBlocked : BOOL;
    RotationFailed : BOOL;
    RotationActive : BOOL;
    InvalidDemand : BOOL;
END_VAR
VAR
    i : INT;
    n : INT;
    Candidate : INT;
    StopCandidate : INT;
    RotOld : INT;
    RotNew : INT;
    RotPhase : INT; (* 0 idle; 1 start replacement; 2 old train shutting down *)
    ReadyCount : INT;
    OccupiedCount : INT;
    LastDemand : INT;
    RotationTarget : INT;
    Desired : INT;
    MinHours : REAL;
    MaxHours : REAL;
    Starting : BOOL;
    Stopping : BOOL;
    OldAck : BOOL;
    OldRotate : BOOL;
    OldReset : BOOL;
    AckEdge : BOOL;
    RotateEdge : BOOL;
    ResetEdge : BOOL;
    SpacingActive : BOOL;
    SpacingReset : BOOL;
    RotationClockReset : BOOL;
    ReplacementLoaded : BOOL;
    tmRecovery : TON;
    tmSpacing : TON;
    tmUp : TON;
    tmDown : TON;
    tmRotation : TON;
    tmOverlap : TON;
    tmRotationTimeout : TON;
END_VAR

ConfigFault := (UnitCount < 1) OR (UnitCount > 16) OR (MaxDuty < 1)
    OR (MaxDuty > UnitCount) OR (MaxParallel < MaxDuty)
    OR (MaxParallel > UnitCount) OR (RecoveryStable <= T#0s)
    OR (StartSpacing <= T#0s) OR (DemandUpDelay < T#0s)
    OR (DemandDownDelay < T#0s) OR (RotationInterval <= T#0s)
    OR (RotationOverlap <= T#0s) OR (RotationTimeout <= RotationOverlap);
n := UnitCount;
IF n < 1 THEN n := 1; END_IF;
IF n > 16 THEN n := 16; END_IF;
AckEdge := AckRecovery AND NOT OldAck;
RotateEdge := RotateNow AND NOT OldRotate;
ResetEdge := ResetAlarm AND NOT OldReset;
OldAck := AckRecovery; OldRotate := RotateNow; OldReset := ResetAlarm;

IF FirstScan THEN
    RecoveryHold := TRUE;
    Target := 0; LastDemand := -1;
    RotPhase := 0; RotOld := 0; RotNew := 0;
    SpacingActive := TRUE; SpacingReset := TRUE; RotationClockReset := TRUE;
    RotationFailed := FALSE;
    AckEdge := FALSE; RotateEdge := FALSE; ResetEdge := FALSE;
    (* Adopt operating trains; never replay a retained command array. *)
    FOR i := 1 TO 16 DO
        Request[i] := (i <= n) AND Status[i].Available
            AND (Status[i].ChillerRunning OR Status[i].Starting);
        IF Request[i] THEN Target := Target + 1; END_IF;
    END_FOR;
END_IF;
IF DisasterActive OR NOT InfrastructureReady THEN RecoveryHold := TRUE; END_IF;

(* Invalid demand freezes the current target; it MUST NOT become zero demand. *)
InvalidDemand := NOT DemandValid OR (Demand < 0) OR (Demand > MaxDuty);
Desired := Target;
IF NOT InvalidDemand THEN Desired := Demand; END_IF;
IF NOT Enable THEN Desired := 0; END_IF;

tmRecovery(IN := InfrastructureReady AND NOT DisasterActive AND NOT FirstScan,
    PT := RecoveryStable);
tmSpacing(IN := SpacingActive AND NOT SpacingReset AND NOT FirstScan, PT := StartSpacing);
tmUp(IN := Enable AND NOT InvalidDemand AND NOT RecoveryHold
    AND (Desired > Target) AND (Desired = LastDemand) AND NOT FirstScan,
    PT := DemandUpDelay);
tmDown(IN := NOT InvalidDemand AND NOT RecoveryHold AND (Desired < Target)
    AND (Desired = LastDemand) AND NOT FirstScan, PT := DemandDownDelay);
tmRotation(IN := Enable AND RotateEnable AND NOT RecoveryHold AND (Target > 0)
    AND (RotPhase = 0) AND NOT RotationClockReset AND NOT FirstScan,
    PT := RotationInterval);
ReplacementLoaded := FALSE;
IF (RotNew >= 1) AND (RotNew <= n) THEN
    ReplacementLoaded := Status[RotNew].Loaded;
END_IF;
tmOverlap(IN := (RotPhase = 1) AND ReplacementLoaded
    AND NOT FirstScan, PT := RotationOverlap);
tmRotationTimeout(IN := (RotPhase <> 0) AND NOT FirstScan, PT := RotationTimeout);
RotationClockReset := FALSE;
SpacingReset := FALSE;
IF tmSpacing.Q THEN SpacingActive := FALSE; END_IF;
IF ResetEdge THEN RotationFailed := FALSE; END_IF;
IF RecoveryHold AND tmRecovery.Q AND (AutoRecovery OR AckEdge) AND Enable
    AND NOT ConfigFault THEN
    RecoveryHold := FALSE;
    SpacingActive := TRUE;
    SpacingReset := TRUE;
END_IF;
IF NOT Enable THEN Target := 0;
ELSIF NOT RecoveryHold AND NOT ConfigFault THEN
    IF tmUp.Q OR tmDown.Q THEN Target := Desired; END_IF;
END_IF;
LastDemand := Desired;

RunningCount := 0; LoadedCount := 0; RequestedCount := 0;
ReadyCount := 0; OccupiedCount := 0;
Starting := FALSE; Stopping := FALSE;
FOR i := 1 TO 16 DO
    IF i <= n THEN
        IF Status[i].ChillerRunning THEN RunningCount := RunningCount + 1; END_IF;
        IF Status[i].Loaded THEN LoadedCount := LoadedCount + 1; END_IF;
        IF Status[i].Ready THEN ReadyCount := ReadyCount + 1; END_IF;
        IF NOT Status[i].Available THEN Request[i] := FALSE; END_IF;
        IF Request[i] THEN RequestedCount := RequestedCount + 1; END_IF;
        IF Request[i] OR Status[i].ChillerRunning OR Status[i].Starting THEN
            OccupiedCount := OccupiedCount + 1;
        END_IF;
        Starting := Starting OR Status[i].Starting;
        Stopping := Stopping OR Status[i].Stopping;
    ELSE
        Request[i] := FALSE;
    END_IF;
END_FOR;

(* Select least-hours available start and greatest-hours stoppable running train.
   Ascending index resolves ties deterministically. *)
Candidate := 0; StopCandidate := 0;
MinHours := 3.0E+38; MaxHours := -1.0;
FOR i := 1 TO n DO
    IF Status[i].Ready AND NOT Request[i] AND (RunHours[i] >= 0.0)
        AND (RunHours[i] < MinHours) THEN
        Candidate := i; MinHours := RunHours[i];
    END_IF;
    IF Request[i] AND Status[i].Loaded AND Status[i].CanStop
        AND (RunHours[i] >= 0.0) AND (RunHours[i] > MaxHours) THEN
        StopCandidate := i; MaxHours := RunHours[i];
    END_IF;
END_FOR;

RotationBlocked := FALSE;
IF RotPhase <> 0 THEN
    (* Bound indices before use. No reliance on short-circuit array evaluation. *)
    IF (RotOld < 1) OR (RotOld > n) OR (RotNew < 1) OR (RotNew > n) THEN
        RotPhase := 0; RotationFailed := TRUE; RotationClockReset := TRUE;
    ELSE
        IF ConfigFault OR RecoveryHold OR NOT Enable OR InvalidDemand
            OR (Target <> RotationTarget) THEN
            (* Keep the original running unit; cancel replacement normally. *)
            IF RotPhase = 1 THEN Request[RotNew] := FALSE; END_IF;
            RotPhase := 0; RotationClockReset := TRUE;
        ELSIF NOT Status[RotOld].Available THEN
            (* Original failed: replacement is now ordinary fault replacement. *)
            RotPhase := 0; RotationClockReset := TRUE;
        ELSIF NOT Status[RotNew].Available OR tmRotationTimeout.Q THEN
            IF RotPhase = 1 THEN Request[RotNew] := FALSE; END_IF;
            RotationFailed := TRUE; RotPhase := 0; RotationClockReset := TRUE;
        ELSIF RotPhase = 1 THEN
            IF Status[RotNew].Loaded AND tmOverlap.Q AND Status[RotOld].CanStop THEN
                Request[RotOld] := FALSE; RotPhase := 2;
            END_IF;
        ELSIF RotPhase = 2 THEN
            IF NOT Status[RotOld].ChillerRunning AND NOT Status[RotOld].Stopping THEN
                RotPhase := 0; RotationClockReset := TRUE;
            END_IF;
        END_IF;
    END_IF;
END_IF;

IF NOT ConfigFault AND NOT RecoveryHold AND Enable
    AND (RotPhase = 0) AND NOT Starting THEN
    IF RequestedCount < Target THEN
        (* Fault replacement bypasses demand debounce, not start spacing or MinOff.
           Failed trains may finish water post-run while a spare starts. *)
        IF (Candidate > 0) AND NOT SpacingActive AND (OccupiedCount < MaxParallel) THEN
            Request[Candidate] := TRUE;
            SpacingActive := TRUE;
            SpacingReset := TRUE;
        END_IF;
    ELSIF (RequestedCount > Target) AND NOT Stopping AND NOT InvalidDemand THEN
        IF StopCandidate > 0 THEN Request[StopCandidate] := FALSE; END_IF;
    ELSIF RotateEnable AND NOT InvalidDemand AND (RotateEdge OR tmRotation.Q) AND (Target > 0)
        AND (RequestedCount = Target) AND (LoadedCount >= Target)
        AND NOT Stopping THEN
        IF (Candidate > 0) AND (StopCandidate > 0) AND NOT SpacingActive
            AND (OccupiedCount < MaxParallel) THEN
            RotOld := StopCandidate; RotNew := Candidate; RotationTarget := Target;
            Request[RotNew] := TRUE; RotPhase := 1; SpacingActive := TRUE;
            SpacingReset := TRUE;
            RotationClockReset := TRUE;
        ELSE RotationBlocked := TRUE;
        END_IF;
    END_IF;
END_IF;
(* Disable is an orderly stop; hard stops are the individual Train.HardTrip input. *)
IF NOT Enable THEN
    FOR i := 1 TO 16 DO Request[i] := FALSE; END_FOR;
END_IF;

RotationActive := RotPhase <> 0;
RequestedCount := 0;
FOR i := 1 TO n DO
    IF Request[i] THEN RequestedCount := RequestedCount + 1; END_IF;
END_FOR;
CapacityShortage := Enable AND NOT InvalidDemand AND (LoadedCount < Demand);
NoStartCandidate := Enable AND NOT RecoveryHold
    AND (RequestedCount < Target) AND (Candidate = 0);
ReserveUnavailable := Enable AND (ReadyCount = 0);
END_FUNCTION_BLOCK
