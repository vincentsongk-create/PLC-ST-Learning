(* 1 s pulse; run time (s) per SOO: unit run time counted from pump status *)
trig_1s (CLK := %S6);
SEC_P := trig_1s.Q;
IF ACH_RUN AND SEC_P THEN ACH_Runtime := ACH_Runtime + 1; END_IF;
IF CHP_RUN AND SEC_P THEN CHP_Runtime := CHP_Runtime + 1; END_IF;
IF Runtime_Reset THEN
    ACH_Runtime := 0;
    CHP_Runtime := 0;
    Runtime_Reset := FALSE;
END_IF;
CH_RUNH := CHP_Runtime / 3600;
ACH_RUNH := ACH_Runtime / 3600;
