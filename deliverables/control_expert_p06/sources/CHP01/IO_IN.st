(* Input conditioning: the logic below only uses these internal variables (eases simulation) *)
IF SIM_EN THEN
    ACH_RUN := SIM_ACH_S;
    CHP_RUN := SIM_CHP_S;
    CHP_FLT_DI := SIM_CHP_F;
    CHP_REM := NOT SIM_CHP_LOCAL;
    ACH_F1 := SIM_ACH_F1;
    PHTS_RUN := PHTS_C;
    PHTS_FLT := FALSE;
    ACH_AM := NOT SIM_ACH_LOCAL;
    ACH_PWR_HW := NOT SIM_PWRLOSS;
ELSE
    ACH_RUN := ACH_S;
    CHP_RUN := CHWP_S;
    CHP_FLT_DI := CHWP_F;
    CHP_REM := CHWP_AM;
    ACH_F1 := ACH_F01;
    PHTS_RUN := PHTS_S;
    PHTS_FLT := PHTS_F;
    (* Chiller remote comes from the chiller Modbus RTU: the comm section writes software point ACH_AM_RTU (initial TRUE) *)
    ACH_AM := ACH_AM_RTU;
    (* Chiller power hardware point ACH_PW (%I0.6.5, 1 = powered; the I/O list wrongly calls it ACH_F02 chiller fault 2) *)
    ACH_PWR_HW := ACH_PW;
END_IF;

(* Chiller powered: PWR_USE_DI=TRUE uses the hardware point; FALSE uses the software point ACH_PWR_RTU
   (To judge power from chiller comm data later: write ACH_PWR_RTU in section Modbus_RTU_COMM and set PWR_USE_DI := FALSE) *)
IF PWR_USE_DI OR SIM_EN THEN
    ACH_PWR := ACH_PWR_HW;
ELSE
    ACH_PWR := ACH_PWR_RTU;
END_IF;

(* SOO: charge flow = CHS-FL01 - CHR-FL01; CHR-FL01 = I/O list AI-1 channel 1 CHWR_FL01 (named CHS_FL02 in the original program) *)
CHG_FL_RET := CHR_FL01;
