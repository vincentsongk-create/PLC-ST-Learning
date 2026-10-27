(* Pipe heat tracing: start when any temperature < PHTS_T_SP (5 °C); stop when all > setpoint + hysteresis (1.1 °C). Fixed T04 <> to > *)
IF (PHTS_T01 < PHTS_T_SP) OR (PHTS_T02 < PHTS_T_SP) OR (PHTS_T03 < PHTS_T_SP) OR (PHTS_T04 < PHTS_T_SP) THEN
    PHTS_Auto_OP := TRUE;
END_IF;
IF (PHTS_T01 > PHTS_T_SP + PHTS_DT_SP) AND (PHTS_T02 > PHTS_T_SP + PHTS_DT_SP)
   AND (PHTS_T03 > PHTS_T_SP + PHTS_DT_SP) AND (PHTS_T04 > PHTS_T_SP + PHTS_DT_SP) THEN
    PHTS_Auto_OP := FALSE;
END_IF;
