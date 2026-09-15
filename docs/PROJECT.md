# 信号分析工具 (SignalAnalysis Tools)

> MATLAB R2025b 信号分析桌面应用，基于 MVP 四层架构。

---

## 1. 项目概述

### 1.1 功能

- **时域分析**：多数据集导入、多通道叠加显示（1-6 个 axes）、归一化、切片、通道运算
- **频谱分析**：FFT / PSD 弹窗查看
- **传函分析**：FRF 频响曲线（幅值/相位/相关性）
- **游标卡尺**：O(1) 索引查找、Y 向智能吸附、悬浮坐标文本、原生 DataTip 标注、动态工程单位
- **数据管理**：Excel 导出、采样率设置、通道重命名、数据集重命名

### 1.2 环境要求

| 项目 | 要求 |
|------|------|
| MATLAB | R2025b 或更高 |
| 必需工具箱 | 无（纯 App Designer + uitable） |
| 可选工具箱 | Signal Processing Toolbox（PSD 分析） |

### 1.3 启动方式

```matlab
cd('D:\00_TODO\ControlSystemMatlab\Tools')
addpath(pwd)
StartApp
```

---

## 2. 目录结构

```
Tools/
├── StartApp.m                  # 入口脚本
├── app/
│   └── SignalAnalysisApp.m     # Layer 1: App Shell（uifigure + uitabgroup）
├── view/
│   ├── TimeSeriesView.m        # Layer 2: 时域分析视图（哑终端）
│   ├── TransferFunctionView.m  # Layer 2: 传函分析视图（哑终端）
│   └── AppEventData.m          # event.EventData 子类（R2025b notify 兼容）
├── presenter/
│   ├── BasePresenter.m         # Presenter 基类（listener 生命周期管理）
│   ├── TimeSeriesPresenter.m   # Layer 3: 时域分析控制层
│   └── TransferFunctionPresenter.m  # Layer 3: 传函分析控制层
├── model/
│   ├── Dataset.m               # 单数据集容器（矩阵 + 列名 + 采样率）
│   └── SessionData.m           # 会话状态容器（多数据集 + axes 通道映射）
├── service/
│   ├── DataReaderFactory.m     # 数据导入（.dat/.csv/.txt → 标准化 .mat）
│   ├── ChannelOperations.m     # 纯函数：通道运算、切片、FRF 提取
│   ├── SignalProcessor.m       # 信号处理：FFT、PSD、归一化
│   └── FileExplorer.m          # 文件/文件夹选择封装
└── docs/
    ├── PROJECT.md              # 本文档
    ├── architecture_analysis.md  # 架构详细分析
    └── UI交互逻辑清单.md        # 全部 UI 交互链路
```

---

## 3. 架构设计

### 3.1 四层 MVP 架构

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: App Shell  (SignalAnalysisApp.m)                  │
│  窗口生命周期、页签管理、状态栏、UI settle                   │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: View  (TimeSeriesView / TransferFunctionView)     │
│  控件装配、渲染、事件广播（哑终端，零业务逻辑）              │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: Presenter  (TimeSeriesPresenter / TF Presenter)    │
│  事件→业务调度、状态协调、弹窗管理                           │
├─────────────────────────────────────────────────────────────┤
│  Layer 4: Model + Service                                   │
│  Dataset / SessionData / DataReaderFactory / ...            │
│  数据容器、纯函数计算、文件 I/O                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 核心设计原则

1. **View 是哑终端**：只做控件装配和渲染，零业务逻辑。通过 `notify` 广播事件，不直接调用 Presenter。
2. **Presenter 是调度中心**：监听 View 事件，调用 Model/Service，再通过 View 的公开方法更新 UI。
3. **单向数据流**：View → Event → Presenter → Model → View.Refresh。
4. **R2025b 兼容**：`notify` 必须传递 `event.EventData` 子类，使用 `AppEventData` 包装 struct 载荷。

### 3.3 事件通信模式

```matlab
% View 广播事件
notify(obj, 'ChannelCheckChanged', AppEventData(struct('datasetIdx', 1, 'colIdx', 2, 'checked', true)));

% Presenter 监听
obj.TrackListener(addlistener(view, 'ChannelCheckChanged', @obj.OnChannelCheckChanged));

% Presenter 处理
function OnChannelCheckChanged(obj, ~, evt)
    d = evt.Data;  % 通过 evt.Data 访问 struct 载荷
    % ... 业务逻辑
end
```

### 3.4 AppEventData（R2025b 必需）

```matlab
classdef AppEventData < event.EventData
    properties (SetAccess = private)
        Data struct
    end
    methods
        function obj = AppEventData(data)
            obj.Data = data;
        end
    end
end
```

---

## 4. 核心模块详解

### 4.1 SignalAnalysisApp — App Shell

**职责**：创建窗口、管理页签、协调 legend 刷新。

**关键机制**：
- `SettleUI()`：40 次 `drawnow` + `pause(0.025)` 泵送渲染队列，解决 `uigridlayout` 惰性布局
- 页签切换 legend 刷新：隐藏页签内创建的 legend 为空条目，通过 `OnMouseMoved` 延迟刷新
- `CloseRequestFcn`：先 delete Presenter，再 delete Figure，杜绝孤儿窗口

### 4.2 TimeSeriesView — 时域视图

**职责**：通道表、动态 axes、工具栏、右键菜单。

**关键属性**：
| 属性 | 说明 |
|------|------|
| `ChannelTable` | uitable（勾选列 + 名称列） |
| `AxesHandles_` | cell 数组，1-6 个 uiaxes |
| `ChannelRows_` | struct 数组：isParent/parentIdx/datasetIdx/colIdx/label/checked |
| `ExpandedSets_` | containers.Map：datasetIdx → 展开状态 |
| `VisibleRowMap_` | 可见行号 → ChannelRows_ 索引映射 |
| `FocusedAxes_` | 当前聚焦的 axes 索引 |
| `Renaming_` | 重命名模式标志（禁用展开/折叠） |
| `Rebuilding_` | 表格重建标志（防止回调重入） |
| `Highlighting_` | 程序设置 Selection 标志（防止回调重入） |

**关键交互**：
- 数据集行点击：展开/折叠子通道
- 复选框勾选：数据集行一键全选/取消，通道行单通道勾选
- 右键菜单：重命名、设置采样频率、导出 Excel、切片
- 重命名流程：右键→重命名 → 临时开启列编辑 → 确认/取消 → 恢复

### 4.3 TimeSeriesPresenter — 时域控制层

**职责**：连接 View 与 Model/Service。

**关键方法**：
| 方法 | 功能 |
|------|------|
| `OnBrowseFolder` | 文件夹选择 → 递归导入 |
| `OnImportFiles` | 多文件选择 → 导入 |
| `AddResultsToSession` | 导入结果加入 Session（跳过重复） |
| `RefreshChannelTable` | 从 Session 重建 ChannelRows_ → View.SetChannelTable |
| `RenderAxes` | 从 Session 读取通道数据 → View.RenderWaveform |
| `OnInlineRenameChannel` | 内联重命名通道（无弹窗）→ 更新 .mat/.json |
| `OnInlineRenameDataset` | 内联重命名数据集（无弹窗）→ 更新 .mat |
| `OnExportDatasetExcel` | 导出 _review.xlsx（文件名使用数据集名） |
| `ShowSpectrumPopup` | FFT/PSD 弹窗 |
| `initCursor` | 初始化游标管理器 + datacursormode 监听 |
| `OnCursorMotion` | O(1) 索引 + 智能吸附 + Marker/HoverText 更新 |
| `OnDataCursorEnableChanged` | DataTip 开关 → 暂停/恢复游标 |
| `CreateDatatip` | 在吸附后的曲线上创建原生 datatip |
| `ClearDatatips` | 清除指定 axes 的 datatip |
| `formatPrecisionValue` | 动态工程单位格式化（mm/um/nm/pm，mm 基准） |

### 4.4 SessionData — 会话状态

**职责**：管理多数据集、axes 通道映射。

**关键方法**：
| 方法 | 功能 |
|------|------|
| `AddDataset(ds, name, path)` | 添加数据集 |
| `UpdateDataset(idx, newDs)` | 替换数据集，同步 axes 通道数据 |
| `SetDatasetName(idx, newName)` | 重命名数据集，同步 axes 通道标签 |
| `GetAxesChannels(axIdx)` | 获取指定 axes 的通道列表 |

### 4.5 DataReaderFactory — 数据导入

**职责**：文件解析、标准化、导入。

**关键方法**：
| 方法 | 功能 |
|------|------|
| `Import(folder)` | 递归扫描文件夹 → 分组 → ProcessFileGroup |
| `ProcessFileGroup(fileStructs, rootDir)` | 同组文件合并 → 标准化 → 保存 .mat |
| `LoadStandard(matPath)` | 加载标准化 .mat → Dataset 对象 |
| `ExtractFrfCurves(ds)` | 从 Dataset 提取 FRF 曲线 |
| `ExportToExcel(matPath, xlsxPath)` | 导出 Excel（列名 + 数据） |
| `GetDirectoryName(filePath, rootDir)` | 提取子目录名（不含根目录名） |

**数据格式**：
- `.mat` 文件：`sa_data_matrix`（数据矩阵）、`sa_column_names`（列名）、`sa_sample_rate`（采样率）
- 可选：`sa_dataset_name`（自定义数据集名）

---

## 5. 数据流

### 5.1 文件导入流程

```
用户点击 Browse/Import
  → Presenter.OnBrowseFolder / OnImportFiles
  → FileExplorer.SelectFolder / SelectFiles
  → DataReaderFactory.Import (递归扫描)
  → DataReaderFactory.ProcessFileGroup (同组合并)
  → DataReaderFactory.LoadStandard (.mat → Dataset)
  → Presenter.AddResultsToSession
    → LoadDatasetName (读取 sa_dataset_name)
    → Session.AddDataset
  → Presenter.RefreshChannelTable → View.SetChannelTable
  → Presenter.RenderAxes → View.RenderWaveform
```

### 5.2 游标卡尺流程

```
鼠标在 axes 内移动
  → View.onCursorMotion (WindowButtonMotionFcn)
  → notify('CursorMotion', {axesIdx, x, mouseY})
  → Presenter.OnCursorMotion
    → O(1) 索引：round((x - x0) / dx) + 1（均匀数据）
    → 防抖：idx == CursorLastIdx_ 则跳过
    → 智能吸附：min(|yVals - mouseY|) → snapY + activeLabel
    → 记录 CursorActiveLine_{axIdx}（供 datatip 使用）
    → 构建 markerData → View.UpdateCursorMarkers（marker + hoverText）
    → 构建 readout → UpdateCursorReadout（readout 面板）
```

### 5.3 DataTip 流程

```
用户点击 DataTip 工具栏按钮
  → datacursormode(fig).Enable → 'on'
  → PostSet 监听触发 → OnDataCursorEnableChanged
  → DataTipActive_ = true, HideCursor
  → 游标暂停（OnCursorMotion 直接 return）

用户在线条上点击
  → MATLAB 模式管理器拦截 → 创建原生 datatip

用户右键
  → OnAxesClicked → ClearDatatips(axesIdx)

用户关闭 DataTip
  → Enable → 'off' → DataTipActive_ = false
  → 下次鼠标移动自动恢复游标
```

### 5.4 通道勾选流程

```
用户勾选复选框
  → View.OnChannelEdit (col==1)
  → View.notify('ChannelCheckChanged')
  → Presenter.OnChannelCheckChanged
  → Session.AddChannel / RemoveChannel
  → Presenter.RenderAxes → View.RenderWaveform
```

### 5.5 重命名流程

```
用户右键 → "重命名"
  → View.OnContextMenuOpening (选中行)
  → View.OnContextRename
    → Renaming_ = true
    → ColumnEditable(2) = true
    → 聚焦名称单元格
  → 用户编辑 → 回车确认
  → View.OnChannelEdit (col==2, Renaming_==true)
    → Renaming_ = false, ColumnEditable(2) = false
    → notify('InlineRenameChannel' / 'InlineRenameDataset')
  → Presenter.OnInlineRenameChannel / OnInlineRenameDataset
    → Session.SetDatasetName / ds.RebuildWithColumnNames
    → save(matPath, ...) 回写 .mat
  → Presenter.RefreshChannelTable + RenderAxes
```

---

## 6. UI 交互清单

详见 [UI交互逻辑清单.md](UI交互逻辑清单.md)。

### 6.1 时域分析交互

| 操作 | 方式 | 效果 |
|------|------|------|
| 展开/折叠数据集 | 左键点击数据集行 | 切换子通道可见性 |
| 勾选通道 | 点击复选框 | 显示/隐藏通道波形 |
| 全选/取消数据集 | 点击数据集复选框 | 一键勾选/取消所有通道 |
| 重命名 | 右键→重命名 | 临时开启列编辑，回车确认 |
| 设置采样频率 | 右键→设置采样频率 | 弹窗输入，回写 .mat/.json |
| 导出 Excel | 右键→导出 Excel | 导出 _review.xlsx |
| 切片 | 右键→设置切片范围 | 弹窗设置起止索引 |
| 游标卡尺 | 鼠标在 axes 内移动 | 红色竖线 + 吸附红圈 + 坐标悬浮文本 |
| DataTip 标注 | 工具栏 DataTip 按钮 + 点击线条 | 创建原生 datatip，游标临时隐藏 |
| 清除 datatip | 右键 axes | 清除当前 axes 的所有 datatip |
| 切换 axes | 左键点击 axes | 高亮红色边框 + 状态栏坐标 |
| 添加/删除 axes | 工具栏 +/- | 动态增减 axes（1-6个） |
| 切换布局 | 工具栏 ‖/= | 单列/双列布局 |
| FFT/PSD | 工具栏按钮 | 弹窗画频谱 |
| 归一化 | Norm 下拉+按钮 | 通道归一化重绘 |
| 通道运算 | Calc 按钮 | 弹窗选运算，生成新数据集 |

### 6.2 传函分析交互

| 操作 | 方式 | 效果 |
|------|------|------|
| 选择路径 | Browse 按钮 | 文件夹选择 |
| 导入 FRF | Import 按钮 | 导入并提取 FRF 曲线 |
| 勾选曲线 | 复选框 | 显示/隐藏曲线 |
| 清空 | Clear All | 清空全部数据和图表 |

---

## 7. 已知机制与注意事项

### 7.1 R2025b notify 兼容

MATLAB R2025b 的 `notify` 不支持 struct 直接传递，必须使用 `event.EventData` 子类。本项目使用 `AppEventData` 包装。

### 7.2 uigridlayout 渲染延迟

`uigridlayout` 使用惰性布局，新创建的控件可能不立即显示。`SettleUI()` 通过多次 `drawnow` 泵送渲染队列解决。

### 7.3 隐藏页签 legend 问题

在隐藏的 `uitab` 内创建的 `legend` 为空条目。解决方案：页签切换时设置标志，鼠标移动时延迟刷新 legend。

### 7.4 数据集名持久化

- 数据集名默认来自目录结构（`GetDirectoryName`）
- 用户重命名后保存为 `.mat` 中的 `sa_dataset_name` 变量
- 导入时 `LoadDatasetName` 优先读取 `sa_dataset_name`
- 导出 Excel 文件名使用当前数据集名

### 7.5 通道标签格式

通道标签格式为 `"数据集名 / 通道名"`，图例仅显示通道名（去掉数据集前缀）。

### 7.6 HitTest 与 DataTip 共存

数据线默认 `HitTest='on'`，每条线设置 `ButtonDownFcn → OnAxesButtonDown`。两条路径自然共存：

- **DataTip 关闭**：点击线条 → 线的 `ButtonDownFcn` → 游标/状态栏正常
- **DataTip 开启**：MATLAB 模式管理器拦截点击 → 创建原生 datatip

`datacursormode(fig).Enable` 的 `PostSet` 监听用于暂停游标（避免游标与 datatip 重叠）。

**注意**：App Designer (`uifigure`) 中 `fig.ModeManager` 不可靠，应使用 `datacursormode(fig)` 或 `uigetmodemanager(fig)`。

### 7.7 重复导入检测

当前基于 `.mat` 文件路径去重（`strcmp(results{i}.matPath, existingPaths)`）。后续计划改为基于数据矩阵 hash 值。

---

## 8. 扩展指南

### 8.1 添加新的右键菜单项

1. **View**：在 `BuildChannelPanel` 的 `uicontextmenu` 中添加 `uimenu`
2. **View**：在 `OnContextAction` 或 `OnContextChannelAction` 中添加 `case`
3. **View**：添加新事件声明
4. **Presenter**：添加 `addlistener` 和处理方法

### 8.2 添加新的工具栏按钮

1. **View**：在 `BuildToolbar` 中添加 `uibutton`
2. **View**：`ButtonPushedFcn` 中 `notify` 新事件
3. **Presenter**：添加监听和处理

### 8.3 添加新的 axes 操作

1. **View**：在 `RenderWaveform` 中添加渲染逻辑
2. **Presenter**：在 `RenderAxes` 中调用 View 方法

---

## 9. 提交历史

| 提交 | 说明 |
|------|------|
| `d6c492e` | DataTip 修复：移除 HitTest='off'，线条加 ButtonDownFcn |
| `a6f3120` | 游标：O(1) 查找、智能吸附、悬浮文本、datatip、工程单位 |
| `6b4ba59` | UI polish: AppEventData 迁移、布局修复、图例改进 |
| `fdcd7ec` | 修复隐藏控件：uigridlayout settle + 延迟 legend 刷新 |
| `b661f40` | Phase 4: 时域 MVP presenter，移除旧 UI |
| `3a1b525` | Phase 3: FRF 传函查看器 |
| `46f65f4` | Phase 2: MVP app shell + uitabgroup |
| `c44dab7` | Phase 1: ChannelOperations + FRF 提取 |
| `8b61f0a` | 核心模块重构 |
| `7259f69` | 初始提交 |

---

## 10. 后续计划

- [ ] 基于数据矩阵 hash 值的重复导入检测
- [ ] 通道运算增强（多数据集间运算）
- [ ] 导出格式扩展（CSV、JSON）
- [ ] 批量处理模式
