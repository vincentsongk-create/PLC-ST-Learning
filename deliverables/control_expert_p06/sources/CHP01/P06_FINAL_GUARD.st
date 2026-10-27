(* P06 final physical-output guard executes AFTER Drive_OP, including manual
   software commands. Independent manufacturer/hardwired safeties remain. *)
P06_AuxPath := (CHV01_FB > CHV_OSTP) AND (CHBPV_FB > 5.0);
P06_RunSafe := ACH_PWR AND ACH_AM AND NOT ACH_F1 AND NOT ACHF_F
    AND NOT CHP_FLT_DI AND CHP_REM AND NOT ALM_CHP_MM
    AND P06_Water AND NOT P06_SeqFault AND NOT P06_ConfigFault
    AND NOT CH_MS AND NOT TST_MS AND (ACH_RUN OR P06_TOff.Q);
IF NOT P06_RunSafe THEN ACH_STC := FALSE; ACH_SPC := TRUE; END_IF;
IF CHP_FLT_DI OR NOT CHP_REM OR ALM_CHP_MM
    OR NOT (P06_Path OR P06_AuxPath) OR P06_Isolatable THEN
    CHP_STC := FALSE; CHP_SPC := TRUE;
END_IF;
