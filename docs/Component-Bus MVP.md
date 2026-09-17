# 🚀 MATLAB V2 全工程重构蓝图 (Component-Bus MVP)

## 👤 角色与工程背景
**角色设定**：你是一位精通 MATLAB 面向对象编程 (OOP)、App Designer 现代 UI 架构以及复杂状态机的高级软体架构师。
**工程背景**：我们正在开发一款【通用的精密运动控制系统数据分析工具】，涵盖时域和频域分析。因处理极高频的诊断数据（例如针对 20-30kg 双驱快门机构，评估 0.5mm 和 0.5mrad 稳态误差等），原有系统出现了严重的“胖视图 (Fat View)”和 UI 强耦合导致的卡顿问题。

---

## 📜 架构宪法 (The Iron Rules)
在编写任何一行代码前，必须自我核对。违反以下铁律的代码将被直接拒收并要求重写：

1. **四层严格隔离架构**：
   * **L4 业务层 (Presenter)**：唯一掌握全局 `SessionData` 的大脑。只能调用 Service 和驱动 View。**绝对禁止**包含任何 UI 控件类名。
   * **L3 中介者视图 (View)**：无状态的事件路由器。实例化 L2 组件，利用 `addlistener` 拦截组件事件并转发给 Presenter。**绝对禁止**包含图表排版或渲染算法。
   * **L2 UI 组件层 (Components)**：继承自 `handle` 的高内聚黑盒（如游标、网格）。**绝对禁止**读取业务 Model 数据！**绝对禁止**互相调用！必须做到“认图不认数据 (Data-Agnostic)”。
   * **L1 渲染引擎**：MATLAB 原生的 `uifigure`, `uiaxes`, `uitable`，仅受 L2 控制。
2. **事件驱动契约 (Event-Driven)**：
   * L2 组件对外的唯一通信方式是：声明原生 `events`，通过 `notify` 发送自定义事件，且必须携带 `AppEventData` 结构体载荷（例如：`struct('action', 'SetX', 'idx', 1)`）。

---

## ⚙️ Agent 自动化执行协议 (Execution Protocol)
你必须按顺序执行以下 5 个 Phase。
**【严格交互流程】**：每完成一个子任务或 Phase，你必须提供源码，并向用户报告：“*该阶段已完成。请检查是否越权。如果没有问题，请发送下一阶段所需的旧代码片段（如有），并准许我进入下一阶段。*” **绝对禁止擅自连续生成！**

---

### 🛠️ Phase 1: L2 独立 UI 组件基建 (UI 拆解)

**任务 1.1：RAII 异步弹窗 (`view/components_v2/AsyncToaster.m`)**
*   **职责**：封装 `uiprogressdlg`。
*   **需求**：继承自 `handle`。构造函数阻断界面；提供 `Update` 方法；**必须重写 `delete(obj)`** 析构函数调用 `close(dlg)`，确保任何异常抛出时弹窗自动销毁。

**任务 1.2：动态画板管理器 (`view/components_v2/AxesGridComponent.m`)**
*   **职责**：接管 `uigridlayout`，负责 1~6 个 `uiaxes` 的动态排版，Data-Agnostic。
*   **需求**：维护 `AxesList` 和 `LayoutMode`。提供增删、清空、获取句柄等接口。每次排版修改后，强制执行 40 次 `drawnow limitrate` 的循环泵送防错位机制。抛出 `AxesAdded` / `AxesRemoved` 事件。

**任务 1.3：无状态通用游标 (`view/components_v2/CursorComponent.m`)**
*   **前提**：【向用户索要旧版关于游标坐标推算的旧代码片段】。
*   **需求**：暴露 `LabelFormatterFcn` 格式化句柄。寻址禁用业务索引推算，使用 `findobj` 获取所有有效 `line`，利用向量化 `min(abs(XData - mouseX))` 寻找交点并就近吸附 Y 轴。处理 `XScale='log'` 的偏移量。加锁 `IsUpdating` 防重入。抛出 `CursorSnapped` 事件。

**任务 1.4：表格与右键状态机 (`view/components_v2/ChannelTableComponent.m`)**
*   **前提**：【向用户索要旧版 `OnContextMenuOpening` 右键拦截逻辑旧代码片段】。
*   **需求**：接管左侧 `uitable`。根据旧代码提取的互斥规则（如：已是横轴不可设为右Y等）控制菜单项 `Enable` 状态。重命名的使能（`ColumnEditable`）在组件内部闭环。所有交互通过 `notify('ActionRequested', ...)` 统一抛出。

---

### 🛠️ Phase 2: L3 中介者主板组装 (View 层空心化)

**任务 2.1：重写主视图 (`view/TimeSeriesView_V2.m`)**
*   **职责**：彻底空心化的事件路由器。
*   **需求**：构造函数中实例化 Phase 1 生成的组件。监听 `GridMgr` 的 `AxesAdded` 事件，动态为新画板实例化 `CursorComponent` 并存入 Map 字典。通过 `addlistener` 拦截表格组件的事件，原样包装为 `AppEventData` 对外抛出给 Presenter。

---

### 🛠️ Phase 3: 剥离领域服务计算层 (Service 提纯)

**任务 3.1：提取数据准备纯函数 (`service/DataPreparationService.m`)**
*   **前提**：【向用户索要旧 Presenter 中乱成一团的数据切片、对齐逻辑代码】。
*   **需求**：编写纯静态算法类。提供类似 `[alignedX, alignedY] = PreparePlotData(...)` 的接口。提取传入的旧逻辑数学内核，负责处理多通道的 `min(length)` 截断、起止时间切片等重度矩阵运算。

---

### 🛠️ Phase 4: L4 业务大脑组装 (Presenter 重生)

**任务 4.1：重写主业务脑 (`presenter/TimeSeriesPresenter_V2.m`)**
*   **职责**：只认数据，不碰 UI 控件。
*   **需求**：
    1. 依赖注入：`function obj = TimeSeriesPresenter_V2(viewHandle, sessionModel)`。
    2. 绝对 UI 隔离：禁止出现图表或表格控件名，UI 变化只能调用 `obj.View.ShowLoading()` 或 `obj.View.RenderWaveforms()` 等宏观指令。
    3. 响应路由：监听 View 转发上来的事件（如 `SetXAxisClicked`）。需要计算时，调用 Phase 3 的 `DataPreparationService` 获取纯数据矩阵，再下发给 View 渲染。

---
**🚀 执行启动令**：如果你已准备就绪，请直接开始 **Phase 1.1**，并在完成后输出代码，等待我的审查。