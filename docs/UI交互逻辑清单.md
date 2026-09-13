# UI 交互逻辑清单

> 审核后请标注需要调整的操作，统一实施。

---

## 一、应用层 (`app/SignalAnalysisApp.m`)

| # | 触发 | 回调 | 行为 |
|---|------|------|------|
| 1 | 启动 `StartApp` | 构造函数 (行26-65) | 创建 `uifigure` → `uigridlayout` → `uitabgroup` → 两个 `uitab`（时域分析、传函分析）→ 实例化 View + Presenter |
| 2 | 切换标签页 | `OnTabChanged` (行94) | 设 `PendingLegendRefresh_=true`，等鼠标移动时刷新 legend |
| 3 | 鼠标移动（切页后首次） | `OnMouseMoved` (行101) | 延迟刷新当前 tab 的 legend |
| 4 | 关闭窗口 | `OnClose` (行115) | 依次 delete 两个 Presenter，再 delete figure |

---

## 二、时域分析 — 工具栏按钮 (`view/TimeSeriesView.m`)

| # | 按钮 | 触发 | 事件 | 载荷 | Presenter 处理 |
|---|------|------|------|------|----------------|
| 1 | `+` | 按钮点击 | `AxesAddClicked` | 无 | **无监听**（View 内部处理，上限6个axes） |
| 2 | `-` | 按钮点击 | `AxesRemoveClicked` | 无 | `OnAxesRemove` → Session.RemoveAxes |
| 3 | `‖` | 按钮点击 | `LayoutChanged` | `{mode:'single'}` | **无监听**（View 内部切换布局） |
| 4 | `=` | 按钮点击 | `LayoutChanged` | `{mode:'dual'}` | **无监听**（View 内部切换布局） |
| 5 | Export | 按钮点击 | `ExportClicked` | 无 | `OnExportFigure` → 复制线条到新 figure |
| 6 | Clear | 按钮点击 | `ClearPlotClicked` | 无 | `OnClearPlot` → 清空所有 axes + session |
| 7 | FFT | 按钮点击 | `FftClicked` | 无 | `ShowSpectrumPopup('fft')` → 弹窗画频谱 |
| 8 | PSD | 按钮点击 | `PsdClicked` | 无 | `ShowSpectrumPopup('psd')` → 弹窗画功率谱 |
| 9 | Norm | 下拉+按钮 | `NormClicked` | `{mode: 'none'/'minmax'/'zscore'/'meanzero'}` | `OnNormalize` → 归一化并重绘 |
| 10 | Calc | 按钮点击 | `CalcClicked` | 无 | `OnCalcChannel` → 弹窗选运算，生成新数据集 |

---

## 三、时域分析 — 左侧面板按钮

| # | 按钮 | 事件 | 载荷 | Presenter 处理 |
|---|------|------|------|----------------|
| 11 | Browse | `BrowseClicked` | 无 | `OnBrowseFolder` → 文件夹选择 → 导入 |
| 12 | Import | `ImportButtonClicked` | 无 | `OnImportFiles` → 多文件选择 → 导入 |
| 13 | Clear All | `ClearAllClicked` | 无 | `OnClearAll` → 清空全部数据集 + axes |

---

## 四、时域分析 — 通道表交互

| # | 操作 | 触发 | 回调 | 事件 | 载荷 | Presenter 处理 |
|---|------|------|------|------|------|----------------|
| 14 | 点击数据集复选框 | CellEdit | `OnChannelEdit`（isParent） | `ChannelCheckChanged` | `{datasetIdx, colIdx:0, checked}` | 一键全选/取消该数据集所有通道 |
| 15 | 点击通道复选框 | CellEdit | `OnChannelEdit`（子行） | `ChannelCheckChanged` | `{datasetIdx, colIdx, checked}` | 单通道勾选/取消 |
| 16 | 点击行（展开/折叠） | CellSelect | `OnChannelSelect` | 无（直接操作） | — | 无（View 内部切换 ExpandedSets_） |
| 17 | 右键→重命名 | 右键菜单 | `OnContextRename` | `InlineRenameChannel` / `InlineRenameDataset` | `{datasetIdx, colIdx, newName}` / `{datasetIdx, newName}` | 内联重命名（无弹窗），回写 .mat/.json |
| 18 | 右键→导出 Excel | 右键菜单 | `OnContextAction('exportExcel')` | `ExportExcelClicked` | `{datasetIdx}` | `OnExportDatasetExcel` → 导出 _review.xlsx（文件名使用数据集名） |
| 19 | 右键→设置采样频率 | 右键菜单 | `OnContextChannelAction('setSampleRate')` | `SetSampleRateClicked` | `{datasetIdx, colIdx}` | `OnSetSampleRate` → inputdlg → 回写 .mat/.json |
| 20 | 右键→设置切片范围 | 右键菜单 | `OnContextChannelAction('slice')` | `SliceDialogClicked` | `{datasetIdx, colIdx}` | `OnSliceDialog` → inputdlg → 设置 slice |
| 21 | 右键→切片重置 | 右键菜单 | `OnContextChannelAction('sliceReset')` | `SliceResetClicked` | `{datasetIdx, colIdx}` | `OnSliceReset` → 恢复全量数据 |

---

## 五、时域分析 — Axes 交互

| # | 操作 | 触发 | 事件 | 载荷 | Presenter 处理 |
|---|------|------|------|------|----------------|
| 23 | 点击 axes | ButtonDownFcn | `AxesClicked` | `{axesIdx, x, y}` | `OnAxesClicked` → 状态栏更新 + `RefreshChannelTable`（同步复选框） |

---

## 六、传函分析 (`view/TransferFunctionView.m`)

| # | 操作 | 触发 | 事件 | 载荷 | Presenter 处理 |
|---|------|------|------|------|----------------|
| 24 | Browse 按钮 | 按钮点击 | `BrowseClicked` | 无 | `OnBrowse` → 文件夹选择 → 写回路径 |
| 25 | Import 按钮 | 按钮点击 | `ImportButtonClicked` | 无 | `OnImport` → 导入 → 提取 FRF 曲线 → 渲染 |
| 26 | 曲线表复选框 | CellEdit | `CurveSelectionChanged` | `{row}`（未被使用） | `OnCurveSelection` → `ApplySelection` → 按勾选状态重绘 |
| 27 | Clear All 按钮 | 按钮点击 | `ClearAllClicked` | 无 | `OnClearAll` → 清空曲线 + 重置路径 + 清空图表 |

---

## 七、未被 Presenter 监听的事件

| 事件 | 原因 |
|------|------|
| `AxesAddClicked` | View 内部完成 axes 创建，无需 Presenter 参与 |
| `LayoutChanged` | View 内部完成布局切换，无需 Presenter 参与 |

---

## 八、Presenter 调用 View 的方法汇总

| View 方法 | 被哪些 Presenter 方法调用 |
|-----------|--------------------------|
| `GetFocusedAxes()` | OnChannelCheckChanged, OnNormalize, OnSliceDialog, OnSliceReset, OnRenameChannel, OnSetSampleRate, OnAxesClicked, ShowSpectrumPopup |
| `GetAxesCount()` | OnAxesRemove, OnExportFigure |
| `GetAxes(idx)` | OnExportFigure, ComputeNormParams |
| `ClearAllAxes()` | OnClearAll, OnClearPlot |
| `ClearAxes(idx)` | RenderAxes |
| `RenderWaveform(...)` | RenderAxes |
| `SetChannelTable(rows)` | RefreshChannelTable（11处调用） |
| `ShowLoading / CloseLoading` | OnBrowseFolder, OnImportFiles, OnExportDatasetExcel |
| `ShowError / ShowInfo` | 多处验证逻辑 |

---

## 九、状态栏消息 (`StatusCallback`)

| 位置 | 消息 |
|------|------|
| `AddResultsToSession` | `'  导入 %d 个数据集'` |
| `OnClearAll` | `' '`（清空） |
| `OnAxesClicked`（有效 axes） | `'  Axes %d  \|  X = %.6g  \|  Y = %.6g'` |
| `OnAxesClicked`（无效） | `' '`（清空） |
| `OnSetSampleRate` | `'  %s 采样率 = %g Hz'` |

---

## 十、右键菜单路由逻辑

```
OnContextMenuOpening()           ← 右键时自动选中最近左键点击的行

OnContextRename()                ← 重命名（数据集行和通道行均可用）
  ├─ 设置 Renaming_=true, ColumnEditable(2)=true
  └─ 用户编辑后 OnChannelEdit(col==2) 确认/取消

OnContextAction(action)          ← 数据集级操作（父行）
  └─ 'exportExcel'               导出 Excel

OnContextChannelAction(action)   ← 通道级操作（子行）
  ├─ 'setSampleRate'             设置采样频率
  ├─ 'slice'                     设置切片范围
  └─ 'sliceReset'                切片重置
```

隐含守卫：`OnContextAction` 跳过子行（`~r.isParent`），`OnContextChannelAction` 跳过父行（`r.isParent`）。

数据集全选/取消：通过点击数据集行复选框实现（`OnChannelEdit` isParent 分支）。

重命名模式：右键→重命名后，`Renaming_=true` 禁用展开/折叠，列2临时可编辑。确认（回车/Tab/点击其他地方）或取消（Escape/名称未变/点击其他行）后恢复。
