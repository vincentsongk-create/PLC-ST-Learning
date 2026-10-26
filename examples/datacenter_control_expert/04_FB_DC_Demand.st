(* Optional supervisory staging by chilled-water SUPPLY temperature.
   Native chiller controllers retain compressor/guide-vane/VFD modulation.
   Do not use with unequal-capacity units without a capacity-based redesign. *)
FUNCTION_BLOCK FB_DC_Demand
VAR_INPUT
    FirstScan : BOOL;
    Enable : BOOL;
    SensorValid : BOOL;
    SupplyTemperature : REAL;
    Setpoint : REAL := 7.0;
    AddBand : REAL := 0.7;
    ShedBand : REAL := 0.5;
    SensorMin : REAL := 0.0;
    SensorMax : REAL := 35.0;
    MinDuty : INT := 1;
    MaxDuty : INT := 3;
    LoadedCount : INT;
    PlantStable : BOOL; (* No starts, stops, rotation, or recovery in progress *)
    AddDelay : TIME := T#120s;
    ShedDelay : TIME := T#600s;
    SettleTime : TIME := T#600s;
END_VAR
VAR_OUTPUT
    Demand : INT;
    DemandValid : BOOL;
    SensorAlarm : BOOL;
    ConfigFault : BOOL;
END_VAR
VAR
    tmAdd : TON;
    tmShed : TON;
    tmSettle : TON;
    Settling : BOOL;
    ResetSettle : BOOL;
    CanAdjust : BOOL;
END_VAR

ConfigFault := (MinDuty < 0) OR (MaxDuty < 1) OR (MaxDuty > 16)
    OR (MinDuty > MaxDuty) OR (AddBand <= 0.0) OR (ShedBand <= 0.0)
    OR (SensorMin >= SensorMax) OR (Setpoint <= SensorMin)
    OR (Setpoint >= SensorMax) OR (AddDelay <= T#0s)
    OR (ShedDelay <= T#0s) OR (SettleTime <= T#0s);
(* Positive range tests also reject an IEEE NaN measurement. *)
SensorAlarm := NOT SensorValid OR NOT ((SupplyTemperature >= SensorMin)
    AND (SupplyTemperature <= SensorMax));
DemandValid := NOT ConfigFault AND NOT SensorAlarm;
IF FirstScan THEN
    Demand := MinDuty;
    IF (LoadedCount > MinDuty) AND (LoadedCount <= MaxDuty) THEN
        Demand := LoadedCount;
    END_IF;
    IF Demand < 0 THEN Demand := 0; END_IF;
    IF Demand > 16 THEN Demand := 16; END_IF;
    Settling := TRUE; ResetSettle := TRUE;
END_IF;
tmSettle(IN := Settling AND NOT ResetSettle AND NOT FirstScan, PT := SettleTime);
ResetSettle := FALSE;
IF tmSettle.Q THEN Settling := FALSE; END_IF;
CanAdjust := Enable AND DemandValid AND PlantStable AND NOT Settling
    AND (LoadedCount = Demand) AND NOT FirstScan;
tmAdd(IN := CanAdjust AND (SupplyTemperature > Setpoint + AddBand)
    AND (Demand < MaxDuty), PT := AddDelay);
tmShed(IN := CanAdjust AND (SupplyTemperature < Setpoint - ShedBand)
    AND (Demand > MinDuty), PT := ShedDelay);
IF NOT Enable THEN
    Demand := 0; Settling := TRUE; ResetSettle := TRUE;
ELSIF DemandValid THEN
    IF Demand < MinDuty THEN
        Demand := MinDuty; Settling := TRUE; ResetSettle := TRUE;
    ELSIF Demand > MaxDuty THEN
        Demand := MaxDuty; Settling := TRUE; ResetSettle := TRUE;
    ELSIF tmAdd.Q THEN
        Demand := Demand + 1; Settling := TRUE; ResetSettle := TRUE;
    ELSIF tmShed.Q THEN
        Demand := Demand - 1; Settling := TRUE; ResetSettle := TRUE;
    END_IF;
END_IF;
(* With invalid measurement Demand is held, not forced to zero. *)
END_FUNCTION_BLOCK
