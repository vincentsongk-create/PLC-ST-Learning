CHPVSD_C_ANA (PV_Real := CHPVSD_C, EU_Max := 100.0, EU_Min := 0.0, Raw_High := 10000.0, Raw_Low := 0.0, AO_Raw => M5_AQ0);
CHV01_C_ANA (PV_Real := CHV01_C, EU_Max := 100.0, EU_Min := 0.0, Raw_High := 10000.0, Raw_Low := 0.0, AO_Raw => M5_AQ1);
CHV02_C_ANA (PV_Real := CHV02_C, EU_Max := 100.0, EU_Min := 0.0, Raw_High := 10000.0, Raw_Low := 0.0, AO_Raw => M5_AQ2);
CHV03_C_ANA (PV_Real := CHV03_C, EU_Max := 100.0, EU_Min := 0.0, Raw_High := 10000.0, Raw_Low := 0.0, AO_Raw => M5_AQ3);
CHBPV_C_ANA (PV_Real := CHBPV_C, EU_Max := 100.0, EU_Min := 0.0, Raw_High := 10000.0, Raw_Low := 0.0, AO_Raw => M5_AQ4);
(* 2026-10-15 bench test (user): chiller setpoint also output on AO channel 6 (0..100 -> 0..10000), besides the Modbus write *)
ACH_TSP_ANA (PV_Real := CHS_TSP_OUT, EU_Max := 100.0, EU_Min := 0.0, Raw_High := 10000.0, Raw_Low := 0.0, AO_Raw => M5_AQ6);
