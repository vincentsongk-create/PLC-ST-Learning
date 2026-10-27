(* Test only: SIM_EN=TRUE simulates pumps, chillers, valves and flow, overriding the ANA_AI results *)
IF SIM_EN THEN
    SIM_CHP_DLY (Condition := CHP_STC AND NOT SIM_CHP_FAIL, SP_Condition_Delay := 3, SEC_P := SEC_P,
                 Condition_OK => SIM_CHP_S);
    SIM_ACH_DLY (Condition := ACH_STC AND SIM_CHP_S AND NOT SIM_ACH_FAIL AND NOT SIM_PWRLOSS,
                 SP_Condition_Delay := 20, SEC_P := SEC_P, Condition_OK => SIM_ACH_S);
    IF SEC_P THEN          (* valve moves 10% per second toward the command *)
        SIM_V1 := SIM_V1 + LIMIT(-10.0, CHV01_C - SIM_V1, 10.0);
        SIM_V2 := SIM_V2 + LIMIT(-10.0, CHV02_C - SIM_V2, 10.0);
        SIM_V3 := SIM_V3 + LIMIT(-10.0, CHV03_C - SIM_V3, 10.0);
        SIM_VB := SIM_VB + LIMIT(-10.0, CHBPV_C - SIM_VB, 10.0);
    END_IF;
    CHV01_FB := SIM_V1; CHV02_FB := SIM_V2; CHV03_FB := SIM_V3; CHBPV_FB := SIM_VB;
    IF SIM_CHP_S THEN
        CHPVSD_FB := CHPVSD_C;
        CHS_FL01 := SIM_FL_NOM * CHPVSD_C / 100.0;
    ELSE
        CHPVSD_FB := 0.0;
        CHS_FL01 := 0.0;
    END_IF;
    IF TST_MODE = 4 THEN CHR_FL01 := CHS_FL01 - SIM_CHG_FL; ELSE CHR_FL01 := CHS_FL01; END_IF;
    CHS_T01 := SIM_CHS_T; CHS_T02 := SIM_CHS_T;
    CHIN_T01 := SIM_CHIN_T; CHR_T01 := SIM_CHR_T;
    PHTS_T01 := SIM_PHTS_T; PHTS_T02 := SIM_PHTS_T; PHTS_T03 := SIM_PHTS_T; PHTS_T04 := SIM_PHTS_T;
    TST_CAP := SIM_TST_CAP;
END_IF;
