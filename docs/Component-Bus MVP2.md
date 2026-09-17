# 🚀 运动台数据分析工具：终极架构重构蓝图 (MVP + CBA)

## 👤 角色与任务目标
**角色**：你是一位精通 MATLAB 面向对象编程 (OOP)、App Designer 现代 UI 架构、以及复杂状态机的高级软体架构师。
**目标**：为一款工业级“精密运动台数据分析工具（处理高频机电采样与 FRF 数据）”进行全盘重构。从“脚本化思维”迈向“软件工程化思维”，彻底消除 UI 线程阻塞、内存泄漏与 Fat View（胖视图）引发的假死问题。

---

## 🏛️ 核心架构设计 (The 4-Tier MVP Architecture)
系统必须按严格的“单向数据流”划分为四个相互解耦的层级。下层对上层一无所知，上层仅通过接口调用下层。

### 1. 宿主与生命周期层 (Host Layer) - `SignalAnalysisApp.m`
*   **职责**：程序唯一入口。创建主窗口 (`uifigure`) 和全局网格布局 (`uigridlayout`)。
*   **内存管控**：接管全局生命周期 (`CloseRequestFcn`)，窗口关闭时显式销毁所有 Presenter 以释放内存。

### 2. 控制与业务层 (Presenter Layer - 系统的大脑)
*   **职责**：持有 View 和 Model 句柄。监听 View 事件，调度底层的 Service 进行重负载计算，将结果更新至 Model 并驱动 View 刷新。
*   **内存防漏机制 (必考项)**：在基类 `BasePresenter` 或各 Presenter 中声明私有元胞数组 `Listeners = {}`。必须重写 `delete` 方法，在销毁时彻底 `delete` 所有监听器对象。
*   **异常收口**：全局的 `try...catch` 集中于此，捕获算法错误后调用 View 的 `ShowError`。

### 3. 视图层 (View Layer - 中介者主板) & L2 UI 组件
*   **L3 中介者主板 (如 `TimeSeriesView`)**：绝对的哑终端。零业务逻辑。内部全量使用 `uigridlayout`，摒弃绝对定位。不写任何绘图代码，只负责实例化 L2 组件，并拦截组件事件转发给 Presenter。
*   **L2 UI 组件层 (Components)**：继承自 `handle` 的高内聚黑盒（如游标、画板网格）。**绝对禁止**读取底层 Dataset！**绝对禁止**互相调用！交互事件只能通过 `notify(obj, 'EventName', AppEventData(payload))` 向上抛出。

### 4. 模型与服务层 (Model & Service Layer - 纯粹的科研基座)
*   **职责**：绝对的无状态纯函数计算与数据承载（如 `ChannelOperations`, `SessionData`），完全不依赖 UI，可在命令行独立调用。

---

## 💣 关键机制排雷指南 (MATLAB Specifics)
在编写代码时，必须严格规避以下 MATLAB 特有的坑：
1. **伪异步防假死**：禁止使用 `parfeval`（易引发 OOM）。重负载时，Presenter 必须调用 View 弹出阻断式 `uiprogressdlg`，强制 `drawnow limitrate` 刷新队列，随后主线程同步读取，完成后关闭弹窗。
2. **大通道渲染降级**：禁止在 UI 中循环生成大量独立的 `uicheckbox`。通道选择必须使用 `uitable`（第一列设为 logical 模拟复选框）以保障大通道数下的渲染性能。

---

## ⚙️ Agent 自动化执行协议 (Execution Protocol)
你必须采用渐进式重构，严格按照以下 4 个阶段（Phases）执行。
**【交互铁律】**：每完成一个 Phase（或子任务），必须提交源码并询问：“*Phase X 已完成。请审查是否越权或违背排雷指南。如无问题，请提供下一阶段所需的旧代码（如有），并准许我进入下一阶段。*”

### 🛠️ Phase 1: 夯实纯粹的数据基座 (Service 层重构)
*   **任务 1.1**：编写 `model/SessionData.m` 和 `model/Dataset.m`（提供只读的数据载体结构定义）。
*   **任务 1.2**：编写 `service/DataPreparationService.m`。向用户索取旧版数据对齐/切片逻辑，抽离为纯函数（如 `PreparePlotData`），确保传入 mock 矩阵单测可通过。

### 🛠️ Phase 2: 搭建现代组件化 UI (L2 组件与 L3 View)
*   **任务 2.1 (RAII 弹窗)**：编写 `view/components/AsyncToaster.m`。利用 `uiprogressdlg` 和 `delete` 析构函数实现防死锁加载动画。
*   **任务 2.2 (动态网格)**：编写 `view/components/AxesGridComponent.m`。接管 `uigridlayout`，动态增删坐标轴。排版后必须执行多次 `drawnow limitrate` 防止 UI 错位。
*   **任务 2.3 (无状态游标)**：【向用户索取旧版游标计算公式】。编写 `view/components/CursorComponent.m`。使用 `findobj` 和向量化 `min(abs(XData-mouseX))` 寻找交点，暴露 `LabelFormatterFcn` 以兼容时域/频域单位。
*   **任务 2.4 (通道表状态机)**：【向用户索取旧版右键拦截代码】。编写 `view/components/ChannelTableComponent.m`。基于 `uitable`，接管勾选、右键鉴权与重命名，对外抛出 `ActionRequested` 事件。
*   **任务 2.5 (组装 L3 主板)**：编写 `view/TimeSeriesView.m`。彻底空心化，组装上述 L2 组件。监听表格事件并原样 `notify` 给上层；监听网格事件动态挂载游标。

### 🛠️ Phase 3: 最小闭环验证 (FRF 传函分析器落地)
*   **任务 3.1**：编写 `presenter/TransferFunctionPresenter.m`（以及对应的 `TransferFunctionView.m`）。
*   **验证标准**：跑通完整链路（点击导入 -> 调用阻断弹窗 -> 调度 IO 获取纯净数据 -> 关闭弹窗 -> 渲染 Bode 图）。明确展示 `Listeners` 元胞数组的注册与 `delete` 清理机制。

### 🛠️ Phase 4: 复杂状态攻坚 (时域分析器落地与宿主组装)
*   **任务 4.1**：编写核心的 `presenter/TimeSeriesPresenter.m`。打通通道表格勾选 -> Presenter 捕获 -> 调用 Service 数据切片 -> 调用 View 渲染引擎更新波形的完整闭环。
*   **任务 4.2**：编写全局入口 `app/SignalAnalysisApp.m`。实例化 `uifigure`、全局 Tab 布局，注入 View 和 Presenter，并在 `CloseRequestFcn` 中显式 `delete` 所有 Presenter 实例。

---
**🚀 启动指令**：如果你已深刻理解了整体工程的目录结构、MVP 分层原则、内存防漏与防假死机制，请直接开始 **Phase 1.1** 的编写，并等待我的验收代码。