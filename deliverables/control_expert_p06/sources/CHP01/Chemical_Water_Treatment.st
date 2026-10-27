(* Chemical water treatment (rewritten per SOO)
   Chiller and pump stopped longer than 3 days (CHE-IN-DELAY) and no other unit in chemical treatment -> CHV01, CHBPV to 60%, then pump at minimum speed for 3 min, chiller stays off
   Fix: delay x86400; pump command wired to OUT_ARB; added 3 min timer; abort at once when the unit is asked to run / maintenance / freeze protection *)
(* 2026-10-19 (user): CHV01 100 % (CHV_CHE is the CHBPV position only) - with CHV02 closed CHBPV alone has no flow path *)
CHE_IDLE := (NOT ACH_RUN) AND (NOT CHP_RUN) AND (NOT ACH_EN);
(* K: test divider for the delay (user, 2026-10-15 bench test); 1 = days as set; MAX guards against K = 0 *)
Chemical_Mode_Condition (Condition := CHE_IDLE AND NOT CH_MS, SP_Condition_Delay := SP_Chemical_Mode_Delay * 86400 / MAX(K, 1),
                         SEC_P := SEC_P, Condition_OK => CHE_DUE);
CHE_ABORT := ACH_EN OR CH_MS OR TST_MS OR FPM_ENA[0];
(* 2026-10-15: the pump cannot run (fault / mismatch / not remote) or a valve does not follow -> leave the chemical mode
   instead of waiting for the 3 min pump run forever; no new start until the cause is gone (alarm reset) *)
IF Chemical_Mode_ENA[0] AND (CHWP_Fault OR ALM_CHP_MM OR ALM_CHV01_MM OR ALM_CHBPV_MM) THEN
    CHE_FAIL := TRUE;
END_IF;
IF ACH_EN OR NOT (CHWP_Fault OR ALM_CHP_MM OR ALM_CHV01_MM OR ALM_CHBPV_MM) THEN
    IF NOT Chemical_Mode_ENA[0] THEN CHE_FAIL := FALSE; END_IF;
END_IF;
CHE_ABORT := CHE_ABORT OR CHE_FAIL;
IF CHE_DUE AND P06_ChemGrant AND (P06_State = 0) AND (NOT Chemical_Mode_ENA[0]) AND (NOT Other_Chemical_Mode_Runing) AND NOT CHE_ABORT THEN
    Chemical_Mode_ENA[0] := TRUE;
    Chemical_Mode_ENA[3] := TRUE;      (* valves moving to position *)
END_IF;
IF Chemical_Mode_ENA[3] AND (CHV01_FB > 95.0) AND (CHBPV_FB > CHV_CHE - 5.0) THEN
    Chemical_Mode_ENA[3] := FALSE;
    Chemical_Mode_ENA[4] := TRUE;      (* pump running *)
END_IF;
Chemical_Stop_Condition (Condition := Chemical_Mode_ENA[4] AND CHP_RUN, SP_Condition_Delay := CHE_CH_PLUSE,
                         SEC_P := SEC_P, Condition_OK => CHE_DONE);
IF CHE_DONE OR CHE_ABORT THEN
    Chemical_Mode_ENA[0] := FALSE;
    Chemical_Mode_ENA[3] := FALSE;
    Chemical_Mode_ENA[4] := FALSE;
END_IF;
