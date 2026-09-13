# 信号分析工具 — 重构后代码全逻辑分析

## Context

用户对项目进行了 MVP 架构重构，需要重新梳理全部代码逻辑。本文档覆盖：
1. **四层架构**分层职责与边界
2. **UI 交互操作逻辑**（每个按钮/控件的完整交互链路）
3. **数据流**（从文件导入到屏幕渲染的全链路）
4. **业务逻辑**（核心算法与状态管理）

---

## 一、四层架构总览

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: App Shell  (SignalAnalysisApp.m)                  │
│  职责：窗口生命周期、页签管理、状态栏、UI settle             │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: View  (TimeSeriesView.m / TransferFunctionView.m) │
│  职责：控件装配、渲染、事件广播（哑终端，零业务逻辑）        │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: Presenter  (TimeSeriesPresenter / TF Presenter)    │
│  职责：事件→业务调度、状态协调、弹窗管理                     │
├─────────────────────────────────────────────────────────────┤
│  Layer 4: Model + Service                                    │
│  Model:  Dataset.m / SessionData.m                          │
│  Service: DataReaderFactory / ChannelOperations /            │
│           SignalProcessor / FileExplorer                     │
│  职责：数据容器、纯函数计算、文件 I/O                        │
└─────────────────────────────────────────────────────────────┘
```

### 1.1 Layer 1: App Shell — `SignalAnalysisApp.m`

| 属性 | 说明 |
|------|------|
| `Fig` | uifigure 主窗口，Position=[100 100 1200 700] |
| `TabGroup` | uitabgroup，两个固定页签：「时域分析」（默认选中）、「传函分析」 |
| `StatusBar` | uilabel 底部 24px 状态栏 |
| `TimeSeriesView_` / `TransferFunctionView_` | 两个 View 实例（依赖注入到对应 tab） |
| `TimeSeriesPresenter_` / `TransferFunctionPresenter_` | 两个 Presenter 实例 |

**关键机制：**

- **SettleUI()**：构造函数末尾调用，40 次 `drawnow` + `pause(0.025)` 泵送渲染队列，解决 uigridlayout 惰性布局导致控件不显示的问题。
- **页签切换 legend 刷新**：`OnTabChanged` 设置 `PendingLegendRefresh_` 标志 → `OnMouseMoved` 检测到标志后调用对应 View 的 `RefreshLegends()`。原因：隐藏页签内创建的 legend 为空条目。
- **CloseRequestFcn**：先 delete 两个 Presenter（触发 BasePresenter.delete 清理 listener + 弹窗），再 delete Fig，杜绝孤儿窗口与监听残留。

### 1.2 Layer 2: View — 哑终端

**共同特征：**
- 只做控件装配与事件广播，零业务逻辑
- 通过 `notify(obj, 'EventName', payload)` 广播事件
- 提供 `ShowLoading` / `CloseLoading` / `ShowError` / `ShowInfo` 弹窗
- `RefreshLegends` + `CleanupBrokenLegends`：页签切换后 legend 修复

**TimeSeriesView 控件清单：**

| 控件 | 类型 | 事件 |
|------|------|------|
| 通道表 (ChannelTable) | uitable | CellEditCallback → `ChannelCheckChanged` |
| 右键菜单 | uicontextmenu | 勾选全部/取消全部/导出Excel/重命名/切片/切片重置 |
| Browse / Import / Clear All | uibutton | `BrowseClicked` / `ImportButtonClicked` / `ClearAllClicked` |
| + / × (axes 增删) | uibutton | 内部管理 AxesCount_，广播 `AxesAddClicked` / `AxesRemoveClicked` |
| \|\| / = (布局切换) | uibutton | `LayoutChanged` |
| Export / Clear Plot | uibutton | `ExportClicked` / `ClearPlotClicked` |
| FFT / PSD | uibutton | `FftClicked` / `PsdClicked` |
| Norm dropdown + Norm button | uidropdown + uibutton | `NormClicked` |
| Calc | uibutton | `CalcClicked` |
| 动态 uiaxes (1-6个) | uiaxes | ButtonDownFcn → `AxesClicked` |

**TransferFunctionView 控件清单：**

| 控件 | 类型 | 事件 |
|------|------|------|
| 路径输入 (PathEdit) | uieditfield | — |
| Browse / Import | uibutton | `BrowseClicked` / `ImportButtonClicked` |
| 曲线勾选表 (CurveTable) | uitable | CellEditCallback → `CurveSelectionChanged` |
| 幅值/相位/相关性 axes | uiaxes ×3 | — |

### 1.3 Layer 3: Presenter — 业务调度

**BasePresenter** 基类：
- `Listeners = {}`：集中存储所有 `addlistener` 句柄
- `PopupFigures = {}`：集中存储衍生弹窗句柄
- `delete()`：遍历销毁所有 listener + popup，防止僵尸对象

**TimeSeriesPresenter** 监听 15 个 View 事件：

| 事件 | 回调 | 功能 |
|------|------|------|
| BrowseClicked | OnBrowseFolder | 选文件夹 → 递归导入 |
| ImportButtonClicked | OnImportFiles | 选文件导入 |
| ClearAllClicked | OnClearAll | 清空全部 |
| ChannelCheckChanged | OnChannelCheckChanged | 通道勾选/取消 |
| AxesRemoveClicked | OnAxesRemove | 移除 axes |
| ExportClicked | OnExportFigure | 导出 legacy figure |
| ExportExcelClicked | OnExportDatasetExcel | 导出 Excel |
| ClearPlotClicked | OnClearPlot | 清空所有 axes 渲染 |
| FftClicked | ShowSpectrumPopup('fft') | FFT 弹窗 |
| PsdClicked | ShowSpectrumPopup('psd') | PSD 弹窗 |
| NormClicked | OnNormalize | 归一化 |
| CalcClicked | OnCalcChannel | 通道运算对话框 |
| RenameChannelClicked | OnRenameChannel | 重命名通道 |
| SliceDialogClicked | OnSliceDialog | 切片设置 |
| SliceResetClicked | OnSliceReset | 切片重置 |
| AxesClicked | OnAxesClicked | 状态栏坐标更新 |

**TransferFunctionPresenter** 监听 3 个 View 事件：

| 事件 | 回调 | 功能 |
|------|------|------|
| BrowseClicked | OnBrowse | 选文件夹 |
| ImportButtonClicked | OnImport | 导入 FRF 数据 |
| CurveSelectionChanged | OnCurveSelection | 曲线勾选变化 → 重绘 |

### 1.4 Layer 4: Model + Service

**Model：**

- `Dataset`：不可变数据容器（Values/ColumnNames/SampleRate/SourcePath/FormatTag/Metadata），支持 GetColumn/GetDisplayLabel/GetColumnRange/RebuildWithSampleRate 等
- `SessionData`：会话状态容器，管理多数据集 + 多 axes 通道叠加 + 归一化模式 + 切片范围，支持事件通知（DatasetsUpdated/ChannelsUpdated）

**Service：**

- `DataReaderFactory`：文件解析工厂（.dat/.csv/.txt/.xlsx/.mat），含缓存、列名简化、FRF 提取
- `ChannelOperations`：通道运算纯函数（ApplySlice/Compute/ComputeStats）
- `SignalProcessor`：信号处理纯函数（ComputeFFTSingleSided/ComputeCumulativeRMS）
- `FileExplorer`：文件/路径 UI 工具（SelectFolder/SelectFiles/SelectFile）

---

## 二、UI 交互操作逻辑（逐操作详解）

### 2.1 时域分析 — 文件导入

#### 操作 A：Browse 文件夹导入

```
用户操作：点击 [Browse...] 按钮
    ↓
View: notify('BrowseClicked')
    ↓
Presenter.OnBrowseFolder:
    ① Session.GetLastPath(1) → 记忆上次路径
    ② FileExplorer.SelectFolder(startPath) → uigetdir 对话框
    ③ 若用户取消 → return
    ④ Session.SetLastPath(1, rootDir) → 更新记忆
    ⑤ View.ShowLoading('导入数据...')
    ⑥ DataReaderFactory.Import(rootDir):
        ├─ DiscoverDirectory(rootDir, {'.dat','.csv','.txt','.xlsx'})
        │   递归扫描，跳过生成文件（_standardized.mat 等）
        ├─ GroupByDirectory(discovered) → 按目录分组
        ├─ 对每个目录：
        │   ├─ CheckDirCache(dirPath, dirFiles)
        │   │   ├─ 有缓存且未过期 → 直接用缓存结果
        │   │   └─ 无缓存/过期 → ProcessFileGroup
        │   │       ├─ ParseAll → ReadDataMatrix（解析每个文件）
        │   │       ├─ 按列数分组：单通道 vs 多通道
        │   │       ├─ 单通道多个 → MergeParsed（合并为多列矩阵）
        │   │       ├─ 多通道 → 各自独立保存
        │   │       └─ SaveStandard → .mat + _meta.json
        │   └─ DeduplicateResults → 按 matPath 去重
        └─ 返回 results: {name, matPath}[]
    ⑦ View.CloseLoading()
    ⑧ AddResultsToSession(results):
        ├─ 跳过已存在的 matPath
        ├─ DataReaderFactory.LoadStandard(matPath) → Dataset
        ├─ Session.AddDataset(ds, name, matPath)
        └─ RefreshChannelTable()
    ⑨ StatusCallback('  导入 N 个数据集')
```

#### 操作 B：Import 文件选择

```
用户操作：点击 [Import] 按钮
    ↓
View: notify('ImportButtonClicked')
    ↓
Presenter.OnImportFiles:
    ① FileExplorer.SelectFiles(startPath, filter) → uigetfile MultiSelect
    ② 构造 fileStructs: [{path, fname}, ...]
    ③ DataReaderFactory.ProcessFileGroup(fileStructs, outputDir)
    ④ AddResultsToSession(results) → 同上
```

### 2.2 时域分析 — 通道勾选与渲染

```
用户操作：在通道表勾选/取消某行
    ↓
View.OnChannelEdit:
    ① 从 ChannelRows_ 取 datasetIdx, colIdx
    ② 读取 table 当前 checked 值
    ③ notify('ChannelCheckChanged', {datasetIdx, colIdx, checked})
    ↓
Presenter.OnChannelCheckChanged:
    ① axIdx = View.GetFocusedAxes() → 当前聚焦的 axes
    ② 若 colIdx==0（整数据集操作）：
        遍历该数据集所有列，调用 SetChannelChecked
    ③ 否则：SetChannelChecked(axIdx, datasetIdx, colIdx, checked)
        ├─ checked=true  → Session.AddChannelToAxes(axIdx, datasetIdx, colIdx)
        │   ├─ 扩展 AxesData_ 容量
        │   ├─ 检查去重（同 dataset+col 不重复添加）
        │   ├─ 构造 chan struct: {DatasetIdx, ColIdx, Data, Label, SliceRange}
        │   ├─ 同步 AxesNormMode_
        │   └─ notify('ChannelsUpdated')
        └─ checked=false → Session.RemoveChannelFromAxes(axIdx, datasetIdx, colIdx)
            └─ notify('ChannelsUpdated')
    ④ RenderAxes(axIdx):
        ├─ Session.GetAxesChannels(axIdx) → chans[]
        ├─ 遍历每个 chan：
        │   ├─ 若有 SliceRange → ChannelOperations.ApplySlice（环缓冲切片）
        │   ├─ ApplyNorm(axIdx, c, sig) → 按归一化模式变换
        │   │   ├─ 'none'   → 不变换
        │   │   ├─ 'minmax' → (sig - minY) / (maxY - minY)
        │   │   ├─ 'zscore' → (sig - meanY) / stdY
        │   │   └─ 'meanzero' → sig - meanY
        │   └─ 构造 xCell/yCell/labels/colorList
        └─ View.RenderWaveform(axesIdx, xCell, yCell, labels, colors):
            ├─ cla(ax) + hold on
            ├─ 逐条 plot(ax, x, y, 'Color', 'DisplayName')
            ├─ hold off + grid on + ylabel
            └─ RefreshLegendFor(ax)
    ⑤ RefreshChannelTable() → 重建通道表（含勾选状态与切片标记）
```

### 2.3 时域分析 — Axes 增删与布局

```
用户操作：点击 [+] 按钮
    ↓
View.OnAddAxesClicked:
    ① 检查 AxesCount_ >= 6 → 报错
    ② AddAxesInternal():
        ├─ AxesCount_++
        ├─ 创建 uiaxes(AxesGrid)
        ├─ 设置 ButtonDownFcn → OnAxesButtonDown(idx, e)
        ├─ AxesHandles_{end+1} = ax
        ├─ RelayoutGrid() → 根据 LayoutMode_ 计算行列，设置 Layout.Row/Column
        └─ LinkXAxes() → linkaxes([valid{:}], 'x') 联动 X 轴
    ③ notify('AxesAddClicked')

用户操作：点击 [×] 按钮
    ↓
View.OnRemoveAxesClicked:
    ① 检查 AxesCount_ <= 1 → 报错
    ② AxesCount_-- → delete 最后一个 uiaxes
    ③ FocusedAxes_ = min(FocusedAxes_, AxesCount_)
    ④ RelayoutGrid + LinkXAxes
    ⑤ notify('AxesRemoveClicked')
        ↓
    Presenter.OnAxesRemove:
        Session.RemoveAxes(View.GetAxesCount() + 1)
        注意：此时 View.GetAxesCount() 已经是减 1 后的值，+1 恢复到原值，
        所以清除的是被删除的 axes 槽位

用户操作：点击 [||] 或 [=]
    ↓
View.OnLayoutClicked(mode):
    ① 若当前已是该模式 → return
    ② SetLayout(mode) → LayoutMode_ = mode → RelayoutGrid()
    ③ notify('LayoutChanged', {mode})
```

### 2.4 时域分析 — Axes 点击聚焦

```
用户操作：点击某个 axes 区域
    ↓
View.OnAxesButtonDown(axesIdx, e):
    ① FocusedAxes_ = axesIdx
    ② UpdateAxesHighlight():
        ├─ 聚焦 axes：Box='on', XColor/YColor=[0.8 0.2 0.2]（红色边框）
        └─ 其他 axes：Box='off', XColor/YColor=[0.15 0.15 0.15]（默认色）
    ③ notify('AxesClicked', {axesIdx, x, y})
        ↓
    Presenter.OnAxesClicked:
        StatusCallback(sprintf('  Axes %d  |  X = %.6g  |  Y = %.6g', ...))
```

### 2.5 时域分析 — 归一化

```
用户操作：选择 dropdown 模式（None/Min-Max/Z-Score/Mean Zero）→ 点击 [Norm]
    ↓
View.OnNormClicked:
    ① 从 NormDropdown 读取当前选项
    ② 映射为 mode key: 'none'/'minmax'/'zscore'/'meanzero'
    ③ notify('NormClicked', {mode})
        ↓
Presenter.OnNormalize:
    ① axIdx = View.GetFocusedAxes()
    ② Session.SetAxesNormMode(axIdx, mode)
    ③ 若 mode='none' → 清空 NormParams
    ④ 否则 → ComputeNormParams(axIdx):
        ├─ 读取 axes 当前 xlim 作为参考窗 [refStart, refEnd]
        ├─ 遍历 axes 所有通道：
        │   ├─ 取 chan.SliceStart（切片偏移）
        │   └─ ChannelOperations.ComputeStats(chan.Data, refStart, refEnd, sliceStart)
        │       → 返回 {minY, maxY, meanY, stdY}
        └─ 返回 normParams = {refWindow, channelStats{}}
    ⑤ Session.SetAxesNormParams(axIdx, normParams)
    ⑥ RenderAxes(axIdx) → 重绘（应用归一化变换）
```

### 2.6 时域分析 — FFT/PSD 弹窗

```
用户操作：点击 [FFT] 或 [PSD]
    ↓
View: notify('FftClicked') 或 notify('PsdClicked')
    ↓
Presenter.ShowSpectrumPopup(analysisType):
    ① axIdx = View.GetFocusedAxes()
    ② chans = Session.GetAxesChannels(axIdx)
    ③ 若空 → 报错
    ④ 创建 uifigure 弹窗（900×700），TrackPopup(fig) 注册生命周期
    ⑤ 上半区 uiaxes：原始时域信号
    ⑥ 下半区 uiaxes：频谱
    ⑦ 遍历每个通道：
        ├─ EnsureSampleRate(chan.DatasetIdx):
        │   ├─ 若 SampleRate 已有 → 直接返回
        │   └─ 否则弹 inputdlg 让用户输入 → Session.UpdateSampleRate
        │       → DataReaderFactory.UpdateSampleRateInMat（回写 .mat）
        ├─ 切片处理：ApplySlice
        ├─ 上图：plot(sampleIdx, sig) 时域波形
        └─ 下图：
            ├─ 'fft' → SignalProcessor.ComputeFFTSingleSided(sig, sr)
            │   → semilogx(freq, P1) 单边幅值谱
            └─ 'psd' → SignalProcessor.ComputeCumulativeRMS(sig, sr)
                → semilogx(freq, cumRms) 累积 RMS 曲线
    ⑧ legend（多通道时显示）
```

### 2.7 时域分析 — 通道运算

```
用户操作：点击 [Calc]
    ↓
View: notify('CalcClicked')
    ↓
Presenter.OnCalcChannel:
    ① 检查有数据集
    ② BuildChannelList() → channelList{N} + channelMap[N×2]
    ③ 创建 uifigure 对话框（380×480），TrackPopup
    ④ UI 控件：
        ├─ 运算类型 dropdown：13 种（A+B, A-B, A×B, A÷B, diff, cumsum, |A|, A², √A, log₁₀, detrend, RMS, smooth）
        ├─ 通道A dropdown + 通道B dropdown（二元运算时启用）
        ├─ A起点/长度 + B起点/长度
        ├─ 窗口大小（smooth 时可见）
        └─ 结果名称（自动生成）
    ⑤ updateOpType() 实时回调：
        ├─ 二元运算 → 启用通道B + B起点/长度
        ├─ smooth → 显示窗口大小
        └─ 自动生成默认结果名
    ⑥ 确定 → doCalc():
        ├─ 读取通道A数据 + 切片 [a1 : a1+aLen-1]
        ├─ 二元运算 → 读取通道B + 切片，校验长度一致
        ├─ diff/cumsum → RequireSampleRateForCalc → EnsureSampleRate
        ├─ smooth → params.windowSize
        ├─ 若 RMS → 计算标量值，弹 uialert 显示，关闭对话框
        ├─ 否则 ChannelOperations.Compute(key, dataA, dataB, params)
        ├─ SaveStandard → LoadStandard → Session.AddDataset
        └─ RefreshChannelTable
```

### 2.8 时域分析 — 切片操作

```
用户操作：右键通道 → [设置切片范围...]
    ↓
View: notify('SliceDialogClicked', {datasetIdx, colIdx})
    ↓
Presenter.OnSliceDialog:
    ① 在聚焦 axes 的通道中查找该 datasetIdx+colIdx
    ② 未找到 → 报错「请先勾选该通道到当前 axes」
    ③ 弹 inputdlg：起点行号 + 长度（当前值回显）
    ④ 校验：起点≥1, 长度≥1
    ⑤ 回绕校验：endRow > totalRows 时，长度不能超过起点
    ⑥ Session.SetChannelSlice(axIdx, chanIdx, startRow, endRow)
    ⑦ RenderAxes + RefreshChannelTable

用户操作：右键通道 → [切片重置]
    ↓
Presenter.OnSliceReset:
    ① 查找通道 → Session.SetChannelSlice(axIdx, chanIdx, 1, length(data))
    ② RenderAxes + RefreshChannelTable
```

### 2.9 时域分析 — 重命名通道

```
用户操作：右键通道 → [重命名通道...]
    ↓
Presenter.OnRenameChannel:
    ① 弹 inputdlg，当前列名回显
    ② Session.GetDataset → ds.RebuildWithColumnNames(newNames)
    ③ Session.UpdateDataset(idx, newDs) → 同步更新 axes 中的通道 Label
    ④ 回写 .mat：save(matPath, 'sa_column_names', '-append')
    ⑤ DataReaderFactory.UpdateColumnNamesInMeta(matPath, newNames) → 更新 _meta.json
    ⑥ RefreshChannelTable + RenderAxes
```

### 2.10 时域分析 — 导出

#### 导出 Figure

```
用户操作：点击 [Export]
    ↓
Presenter.OnExportFigure:
    ① 创建 legacy figure
    ② 遍历所有 axes：
        ├─ subplot(n, 1, i, 'Parent', fig)
        ├─ findobj(ax, 'Type', 'line') → 提取所有线条
        ├─ 逐条 plot(sub, XData, YData, Color/LineStyle/LineWidth/Marker/DisplayName)
        ├─ grid on + title + ylabel
        └─ 多线条时 legend
```

#### 导出 Excel

```
用户操作：右键数据集 → [导出 Excel(本数据集)]
    ↓
Presenter.OnExportDatasetExcel:
    ① Session.GetDatasetMatPath(datasetIdx)
    ② xlsxPath = strrep(matPath, '_standardized.mat', '_review.xlsx')
    ③ DataReaderFactory.ExportToExcel(matPath, xlsxPath):
        ├─ load(matPath) → sa_data_matrix + sa_column_names
        ├─ 构造 cell 矩阵：第1行列名 + N行数据
        └─ writecell(allData, xlsxPath)
    ④ View.ShowInfo('已导出: ...')
```

### 2.11 传函分析 — 导入与渲染

```
用户操作：输入路径 → 点击 [Browse...] → 点击 [Import]
    ↓
TransferFunctionPresenter.OnBrowse:
    FileExplorer.SelectFolder → View.SetPath(folder)

TransferFunctionPresenter.OnImport:
    ① View.GetPath()
    ② 判断路径类型：
        ├─ 文件夹 → DataReaderFactory.Import(path)
        └─ 文件 → ProcessFileGroup(单文件)
    ③ 遍历 results：
        ├─ LoadStandard(matPath) → Dataset
        └─ DataReaderFactory.ExtractFrfCurves(ds) → curves[]
            ├─ 4列 → 单曲线 [amp, phase, corr, freq]
            ├─ 4K列 → K条曲线，每4列一组
            └─ 3K+1列 → 共享Freq + K组 [amp, phase, corr]
    ④ Curves_ = curves
    ⑤ View.SetCurveList({curves.name}, [])
    ⑥ ApplySelection():
        ├─ View.GetCurveSelection() → checked 逻辑数组
        └─ View.RenderFrf(curves(checked)):
            ├─ ClearPlots → cla 三个 axes
            ├─ 遍历选中曲线：
            │   ├─ mask = freq > 0（跳过 f=0）
            │   ├─ semilogx(AmpAxes, freq, amp)
            │   ├─ semilogx(PhaseAxes, freq, phase)
            │   └─ semilogx(CorrAxes, freq, corr) + ylim([0 1])
            └─ RefreshLegends

用户操作：在曲线表勾选/取消
    ↓
View.OnCurveEdit → notify('CurveSelectionChanged')
    ↓
Presenter.OnCurveSelection → ApplySelection → 重绘三图
```

---

## 三、数据流全链路

### 3.1 文件导入数据流

```
原始文件 (.dat/.csv/.txt/.xlsx)
    │
    ▼ ReadDataMatrix(filePath)
    ├─ ParseDatFile: FDOT二进制 → FDOT文本 → SWPP → ACS SWPP → MultiSection → GenericText
    ├─ ParseCsvFile: 自动检测头行数
    ├─ ParseTxtFile: load()
    ├─ ParseExcelFile: readmatrix()
    └─ 返回 [data, rawNames, formatTag]
    │
    ▼ MatchColumnNames(rawNames, data)
    ├─ 检测首列 time/index（递增整数 or 等间隔时间轴）
    ├─ CleanRawName 管线：StripVendorPrefix → 分隔符检测 → 关键字剥离
    ├─ DeduplicateNames（重复名加 _2, _3 后缀）
    └─ 对齐列名与数据列
    │
    ▼ SaveStandard(data, colNames, outputDir, baseName, sourcePath, formatTag)
    ├─ 写 .mat: sa_data_matrix, sa_sample_rate, sa_column_names,
    │           sa_units, sa_descriptions, sa_source_file, sa_source_format, sa_import_time
    └─ 写 _meta.json: source_file, source_format, data_hash, source_stats,
                       import_time, row_count, column_count, sample_rate, columns[]
    │
    ▼ LoadStandard(matPath)
    ├─ 加载 .mat 字段
    ├─ 读取 _meta.json（覆盖 units/descriptions/sampleRate）
    └─ 构造 Dataset(values, colNames, sampleRate, sourcePath, formatTag, metadata, units, descriptions)
    │
    ▼ Session.AddDataset(ds, name, matPath)
    ├─ Datasets_{end+1} = ds
    ├─ DatasetNames_{end+1} = name
    ├─ DatasetPaths_{end+1} = matPath
    └─ notify('DatasetsUpdated')
```

### 3.2 通道渲染数据流

```
Session.GetAxesChannels(axesIdx)
    │
    ▼ 返回 chans{} — 每个 chan 结构体：
    │  {DatasetIdx, ColIdx, Data[N×1], Label, SliceRange[1×2]}
    │
    ▼ 遍历每个 chan：
    ├─ ApplySlice(chan.Data, startRow, endRow)
    │   ├─ endRow ≤ N → signal(startRow:endRow)
    │   └─ endRow > N → [signal(startRow:N); signal(1:endRow-N)]  环缓冲
    │
    ├─ ApplyNorm(axesIdx, chanIdx, sig)
    │   ├─ 'none'   → 不变
    │   ├─ 'minmax' → (sig - minY) / (maxY - minY)
    │   ├─ 'zscore' → (sig - meanY) / stdY
    │   └─ 'meanzero' → sig - meanY
    │   注：minY/maxY/meanY/stdY 来自 ComputeStats 计算的参考窗统计量
    │
    ▼ View.RenderWaveform(axesIdx, xCell, yCell, labels, colors)
    ├─ cla(ax) + hold on
    ├─ plot(ax, x, y, 'Color', 'DisplayName')
    ├─ hold off + grid + ylabel
    └─ RefreshLegendFor(ax)
```

### 3.3 缓存验证数据流

```
DataReaderFactory.Import(rootDir)
    │
    ▼ DiscoverDirectory → 发现所有源文件
    ▼ GroupByDirectory → 按目录分组
    │
    ▼ 对每个目录 CheckDirCache(dirPath, dirFiles):
    ├─ 扫描 *_standardized.mat 文件
    ├─ 读取每个 .mat 对应的 _meta.json → source_file
    ├─ 按 source_file 分组，同一源文件保留最新缓存
    │
    ├─ 检查1：源文件覆盖完整性
    │   └─ 有源文件不在缓存覆盖范围 → isStale = true
    │
    ├─ 检查2：数据 hash 比对
    │   ├─ 快速预检：当前文件 bytes+datenum vs 缓存记录的 source_stats
    │   │   └─ 匹配 → 跳过（未变化）
    │   └─ 预检不通过 → 深度检查：
    │       ├─ ReadDataMatrix 重新解析
    │       ├─ ComputeDataHash(data) → SHA-256
    │       └─ 与缓存 data_hash 比对 → 不同则 isStale = true
    │
    ├─ isStale=true → 清理旧缓存（.mat + _meta.json + _review.xlsx）
    └─ isStale=false → 返回缓存结果列表
```

---

## 四、核心业务逻辑

### 4.1 列名简化管线 (`CleanRawName`)

```
输入: 'VM4A_BLADE_AX_Y2=>CTRL_ERROR'
    │
    ▼ StripVendorPrefix → 'BLADE_AX_Y2=>CTRL_ERROR'   (去掉 VM4A_)
    ▼ 分隔符检测：找到 '=>' 位置
    ▼ 左右分离：
    │   left  = 'BLADE_AX_Y2'
    │   right = 'CTRL_ERROR'
    ▼ 各自独立清理：
    │   left:  StripVendorPrefix → 'BLADE_AX_Y2'
    │          StripKeywordPrefix → 'BLADE_AX_Y2' (AX 不是开头关键字)
    │          TrailingSegment → 'Y2'
    │   right: StripVendorPrefix → 'CTRL_ERROR'
    │          StripKeywordPrefix → 'ERROR' (CTRL 是关键字，剥离)
    │          TrailingSegment → 'ERROR'
    ▼ 拼接: 'Y2_ERROR'
```

### 4.2 .dat 格式自动探测 (`ParseDatFile`)

```
输入: filePath
    │
    ▼ 按优先级尝试 5 种解析器：
    │  ① ParseFdotBinary  → [4B col][4B row][N×M×8B double]
    │  ② ParseFdotText    → 1行标题 + 1行列名 + tab分隔数据
    │  ③ ParseSwppText    → 5行元数据 + N行列名 + 空格/制表数据
    │  ④ ParseAcsSwpp     → step/variable 结构
    │  ⑤ ParseMultiSection → 多段自定义格式
    │
    ▼ 对每个成功解析的结果：
    │  ValidateStructure(d) → 验证行≥2, 列≥1, 无全NaN列, NaN<50%, 无Inf
    │  ComputeConfidence(d) → 置信度评分:
    │      基础50 + 行数奖励(10/20) + 列数奖励(15) - NaN惩罚 + 平滑性奖励(15)
    │
    ▼ 选最高分结果
    ▼ 若全部失败 → ParseGenericText 兜底（跳过非数值行，提取列名）
    ▼ 仍失败 → 报错
```

### 4.3 FRF 曲线提取 (`ExtractFrfCurves`)

```
输入: Dataset (nCols 列)
    │
    ├─ nCols == 4 → 单曲线: [amp(1), phase(2), corr(3), freq(4)]
    │
    ├─ nCols % 4 == 0 → 4K 列布局:
    │   每 4 列一组: [amp, phase, corr, freq]
    │   共 K 条曲线
    │
    ├─ (nCols-1) % 3 == 0 && nCols > 4 → 共享频率布局:
    │   第 1 列 = 共享 Freq
    │   后续每 3 列: [amp, phase, corr]
    │   共 K = (nCols-1)/3 条曲线
    │
    └─ 其他 → 报错 'InvalidFrfLayout'
```

### 4.4 FFT 单边幅值谱 (`ComputeFFTSingleSided`)

```
输入: signal[N×1], sampleRate
    │
    ▼ N = length(signal)
    ▼ w = hann(N, 'periodic') → 周期 Hann 窗
    ▼ Y = fft((signal - mean(signal)) .* w) → 去均值 + 加窗 + FFT
    ▼ P2 = abs(Y / sum(w)) → 归一化幅值
    ▼ P1 = P2(1:floor(N/2)+1) → 取前半段
    ▼ P1(2:end-1) = 2*P1(2:end-1) → 单边修正（×2）
    ▼ f = sampleRate * (0:floor(N/2)) / N → 频率轴
    │
    返回: P1[K×1], f[K×1]
```

### 4.5 累积 RMS (`ComputeCumulativeRMS`)

```
输入: signal[N×1], sampleRate
    │
    ▼ nfft = min(N, 2^nextpow2(max(64, floor(N/4))))
    ▼ [pxx, f] = pwelch(signal, hann(nfft), nfft/2, nfft, sampleRate)
    │   → Welch 法估计功率谱密度
    ▼ df = f(2) - f(1) → 频率分辨率
    ▼ cumRms = sqrt(cumsum(pxx) * df) → 累积 RMS = √(∫PSD·df)
    ▼ totalRms = cumRms(end) → 总 RMS
    │
    返回: cumRms[K×1], f[K×1], totalRms
```

### 4.6 通道运算分派 (`ChannelOperations.Compute`)

```
二元运算（需 A、B 等长）:
    'add'  → A + B
    'sub'  → A - B
    'mul'  → A .* B
    'div'  → A ./ B (B=0 → NaN)

一元运算:
    'diff'    → diff(A) * sampleRate        (需采样率)
    'cumsum'  → cumsum(A) / sampleRate       (需采样率)
    'abs'     → |A|
    'square'  → A²
    'sqrt'    → √|A|
    'log10'   → log₁₀(|A| + eps)
    'detrend' → detrend(A)                   (去趋势)
    'rms'     → √(mean(A²))                  (返回标量)
    'smooth'  → movmean(A, windowSize)       (需窗口大小)
```

### 4.7 归一化参考窗统计 (`ComputeStats`)

```
输入: signal[N×1], refStart, refEnd, sliceStart
    │
    ▼ refStartLocal = max(1, refStart - sliceStart + 1)
    ▼ refEndLocal = min(N, refEnd - sliceStart + 1)
    │   → 将视图坐标映射回数据坐标
    ▼ 若 refStartLocal >= refEndLocal → 回退全窗 [1, N]
    ▼ refSig = signal(refStartLocal:refEndLocal)
    │
    返回: {minY, maxY, meanY, stdY}
```

### 4.8 SessionData 状态管理

```
数据结构:
    Datasets_     {Dataset1, Dataset2, ...}    多数据集
    DatasetNames_ {'Test1', 'Test2', ...}       数据集名
    DatasetPaths_ {path1, path2, ...}           数据集路径
    AxesData_     {struct1, struct2, ...}       每个 axes 的通道列表
        struct.Channels = {chan1, chan2, ...}
            chan.DatasetIdx  → 指向哪个数据集
            chan.ColIdx      → 指向哪一列
            chan.Data        → 数据副本 [N×1]
            chan.Label       → 显示标签 '数据集名 / 列名'
            chan.SliceRange  → [startRow, endRow]
    AxesNormMode_  {'none', 'minmax', ...}      每个 axes 的归一化模式
    AxesNormParams_ {struct1, struct2, ...}     每个 axes 的归一化参数
    FocusedAxes_   double                       当前聚焦 axes 索引
    MaxAxes_       6                            axes 数量上限
    LastPaths_     {path1, path2, path3, path4} 路径记忆（4 个槽位）

事件:
    DatasetsUpdated → 数据集增删时触发
    ChannelsUpdated → axes 通道变化时触发

关键操作:
    AddDataset → 追加数据集 + notify
    RemoveDataset → 移除 + 更新所有 axes 中的 DatasetIdx 引用（被删之前的索引 -1）
    UpdateDataset → 替换数据集 + 同步更新通道 Data 和 Label
    AddChannelToAxes → 添加通道（去重检查）+ notify
    RemoveChannelFromAxes → 移除通道 + notify
    SetChannelSlice → 设置切片范围 + notify
    UpdateSampleRate → 用新采样率重建 Dataset + 同步更新通道 Data + notify
```

---

## 五、测试覆盖

| 测试文件 | 测试数 | 覆盖范围 |
|----------|--------|----------|
| TestChannelOperations.m | 17 | ApplySlice(4) + Compute(10) + ComputeStats(3) |
| TestExtractFrfCurves.m | 5 | 4列单曲线 + 8列双曲线 + 7列共享频率 + 无效布局 + DSA样例文件 |

**未覆盖：**
- DataReaderFactory 解析逻辑（各格式 parser）
- SessionData 状态管理
- Presenter 业务流程
- View 渲染正确性

---

## 六、文件清单

| 文件 | 行数 | 层 | 职责 |
|------|------|-----|------|
| `StartApp.m` | 10 | 入口 | 设置路径，启动 app |
| `app/SignalAnalysisApp.m` | 128 | L1 Shell | 窗口 + 页签 + 状态栏 + 生命周期 |
| `view/TimeSeriesView.m` | 494 | L2 View | 时域分析 UI 装配 + 渲染 + 事件广播 |
| `view/TransferFunctionView.m` | 216 | L2 View | 传函分析 UI 装配 + 渲染 + 事件广播 |
| `presenter/BasePresenter.m` | 41 | L3 Presenter | Listener/Popup 生命周期基类 |
| `presenter/TimeSeriesPresenter.m` | 829 | L3 Presenter | 时域分析业务逻辑调度 |
| `presenter/TransferFunctionPresenter.m` | 97 | L3 Presenter | 传函分析业务逻辑调度 |
| `model/Dataset.m` | 206 | L4 Model | 不可变数据容器 |
| `model/SessionData.m` | 411 | L4 Model | 会话状态管理 |
| `service/DataReaderFactory.m` | 2337 | L4 Service | 文件解析 + 缓存 + FRF 提取 |
| `service/ChannelOperations.m` | 157 | L4 Service | 通道运算纯函数 |
| `service/SignalProcessor.m` | 53 | L4 Service | FFT/PSD 纯函数 |
| `service/FileExplorer.m` | 148 | L4 Service | 文件选择 UI 工具 |
| `tests/TestChannelOperations.m` | 107 | Test | 通道运算单测 |
| `tests/TestExtractFrfCurves.m` | 74 | Test | FRF 提取单测 |
