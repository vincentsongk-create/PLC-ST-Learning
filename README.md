# PLC-ST-Learning
PLC-ST-Learning

## 数据中心冷站（施耐德 Control Expert）

[使用说明、顺控状态与接口定义](docs/数据中心冷站_ControlExpert_使用说明.md)

[ST 参考源码](examples/datacenter_control_expert/)包含单机水系统顺控、群控加减机、运行时间轮换、故障补机和失电恢复，以及四机三用一备的调用示例。

适用基线为独立配套水设备的等容量冷机；需在 Control Expert 中建立 DDT/DFB、适配现场 I/O，并完成编译及 FAT/SAT，不能将参考文件直接作为已验证的投运工程。
