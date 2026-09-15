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
| 2 | `-` | 按钮点击 | `AxesRemoveClicked` | 无 | `OnAxesRemove` → Session.RemoveAxes + SyncViewAxisState + RefreshChannelTable |
| 3 | `‖` | 按钮点击 | `LayoutChanged` | `{mode:'single'}` | **无监听**（View 内部切换布局） |
| 4 | `=` | 按钮点击 | `LayoutChanged` | `{mode:'dual'}` | **无监听**（View 内部切换布局） |
| 5 | Export | 按钮点击 | `ExportClicked` | 无 | `OnExportFigure` → 复制线条到新 legacy figure（支持双Y轴 + 自定义横轴） |
| 6 | Clear | 按钮点击 | `ClearPlotClicked` | 无 | `OnClearPlot` → 清空所有 axes + session + SyncViewAxisState + RefreshChannelTable |
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
| 13 | Clear All | `ClearAllClicked` | 无 | `OnClearAll` → 清空全部数据集 + axes + SyncViewAxisState + RefreshChannelTable |

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
| 22 | 右键→设为横轴 | 右键菜单 | `OnContextChannelAction('setXAxis')` | `SetXAxisClicked` | `{datasetIdx, colIdx}` | `OnSetXAxis` → Session.SetXChannel + SyncViewAxisState + RenderAxes + RefreshChannelTable |
| 23 | 右键→恢复默认横轴 | 右键菜单 | `OnContextChannelAction('clearXAxis')` | `ClearXAxisClicked` | `{axesIdx}` | `OnClearXAxis` → Session.ClearXChannel + SyncViewAxisState + RenderAxes + RefreshChannelTable |
| 24 | 右键→设为右 Y 轴 | 右键菜单 | `OnContextChannelAction('setRightY')` | `SetRightYAxisClicked` | `{datasetIdx, colIdx}` | `OnSetRightYAxis` → Session.SetRightYChannel（追加到列表）+ SyncViewAxisState + RenderAxes + RefreshChannelTable |
| 25 | 右键→恢复默认 Y 轴 | 右键菜单 | `OnContextChannelAction('clearRightY')` | `ClearRightYAxisClicked` | `{axesIdx}` | `OnClearRightYAxis` → Session.ClearRightYChannel（清除全部右Y）+ SyncViewAxisState + RenderAxes + RefreshChannelTable |

---

## 五、时域分析 — Axes 交互

| # | 操作 | 触发 | 事件 | 载荷 | Presenter 处理 |
|---|------|------|------|------|----------------|
| 26 | 点击 axes/线条 | ButtonDownFcn | `AxesClicked` | `{axesIdx, x, y}` | `OnAxesClicked` → SyncViewAxisState + 状态栏更新（含自定义横轴数据集名） |
| 27 | 右键 axes/线条 | ButtonDownFcn | `AxesClicked` | `{axesIdx, x, y}` | `OnAxesClicked` → `ClearDatatips(axesIdx)` |
| 28 | 鼠标在 axes 内移动 | WindowButtonMotionFcn | `CursorMotion` | `{axesIdx, x, mouseY}` | `OnCursorMotion` → O(1) 索引 + 智能吸附 + Marker/HoverText 更新 |

**点击路由机制**：

数据线默认 `HitTest='on'`，每条线设置 `ButtonDownFcn → OnAxesButtonDown(axesIdx, e)`。点击穿透路径：
- 点击线条 → 线的 `ButtonDownFcn` 触发 → `OnAxesButtonDown` → `AxesClicked` 事件
- 点击空白区域 → axes 的 `ButtonDownFcn` 触发 → `OnAxesButtonDown` → `AxesClicked` 事件

两条路径汇入同一个处理器，游标/状态栏/DataTip 互不干扰。

---

## 六、右键菜单可用性逻辑 (`OnContextMenuOpening`)

右键菜单打开时，根据当前选中通道的状态动态启用/禁用菜单项：

| 菜单项 | 启用条件 | 说明 |
|--------|----------|------|
| 设为横轴 | `isChannel && ~isXChannel` | 非横轴通道可用 |
| 恢复默认横轴 | `isChannel && isXChannel` | 当前是横轴时可用 |
| 设为右 Y 轴 | `isChannel && ~isRightY && ~isXChannel` | 非右Y且非横轴时可用 |
| 恢复默认 Y 轴 | `isChannel && isRightY` | 当前是右Y时可用 |

**变量定义：**
- `isChannel`：选中行是通道行（非数据集父行）
- `isXChannel`：选中通道是当前 axes 的横轴通道
- `isRightY`：选中通道在当前 axes 的右Y通道列表中

**互斥规则：**
- 同一通道不能同时为横轴和右Y轴
- 设为横轴时，如果该通道已是右Y，弹出错误提示 `'该通道已设为右 Y 轴，请先恢复'`
- 设为右Y时，如果该通道已是横轴，弹出错误提示 `'该通道已设为横轴，请先恢复'`

---

## 七、自定义横轴逻辑

### 7.1 数据流

```
Session.SetXChannel(axIdx, datasetIdx, colIdx)
  → AxesXChannel_{axIdx} = struct('DatasetIdx', d, 'ColIdx', c)

Presenter.RenderAxes(axesIdx)
  → [xDsIdx, xColIdx] = Session.GetXChannel(axesIdx)
  → hasXChannel = ~isempty(xDsIdx)
  → xRaw = Session.GetDataset(xDsIdx).GetColumn(xColIdx)
  → SliceChannel(chan, xRaw, hasXChannel)
      → 若有切片：先对 xRaw 和 chan.Data 做 ApplySlice，再 min(length) 截断对齐
      → 若无切片：直接 min(length) 截断对齐
  → View.RenderWaveform(axesIdx, xCell, yCell, ...)
      → xCell{k} 作为 plot 的 XData
```

### 7.2 横轴通道排除

被设为横轴的通道不参与左Y渲染循环（`continue` 跳过），避免自引用对角线。

### 7.3 归一化与自定义横轴

`ComputeNormParams` 使用逻辑索引将 xlim 物理坐标映射到数据范围：
```matlab
mask = xSig >= xl(1) & xSig <= xl(2);
refSig = sig(mask);
```
而非 `round(xlim)` 索引方式（仅适用于默认索引横轴）。

### 7.4 状态栏显示

自定义横轴时，状态栏显示数据集名：
```
Axes 1  |  X = 1234.56 (DRFDOT)  |  Y = 0.789
```

### 7.5 导出 Figure 的 X 标签

导出时 X 轴标签格式：`数据集名 / 列名`（含列名信息）。

---

## 八、多右Y轴逻辑

### 8.1 数据结构

`SessionData.AxesRightYChannel_` 存储格式：
```matlab
AxesRightYChannel_{axIdx} = {
    struct('DatasetIdx', 1, 'ColIdx', 3),   % 第1个右Y通道
    struct('DatasetIdx', 1, 'ColIdx', 5),   % 第2个右Y通道
    ...
}
% 无右Y时为空 cell: {}
```

### 8.2 添加/移除

| 操作 | Session 方法 | 行为 |
|------|-------------|------|
| 设为右Y | `SetRightYChannel(axIdx, d, c)` | 追加到列表（自动去重） |
| 恢复默认Y | `ClearRightYChannel(axIdx)` | 清空整个列表 |
| 取消勾选通道 | `RemoveChannelFromAxes(axIdx, d, c)` | 从列表中移除匹配项 |
| 删除数据集 | `RemoveDataset(idx)` | 遍历列表，移除匹配项，大于 idx 的 DatasetIdx 减1 |
| 清空 axes | `ClearAxes(axIdx)` | 清空整个列表 |
| 删除 axes | `RemoveAxes(idx)` | 清空整个列表 |
| 清空全部 | `ClearAllDatasets` | 清空整个容器 |

### 8.3 渲染流程

```
Presenter.RenderAxes(axesIdx)
  → rightYRefs = Session.GetRightYChannel(axesIdx)   % cell array of structs
  → hasRightY = ~isempty(rightYRefs)

  → 构建右Y查找表 rightYSet (containers.Map)
      → key = sprintf('%d_%d', DatasetIdx, ColIdx)

  → 左Y循环：跳过右Y通道（rightYSet.isKey）和X轴通道

  → 右Y数据收集：
      for ri = 1:length(rightYRefs)
          → FindChannelInList → SliceChannel → 构建 rightYData
      end
      rightYData = struct('x', {rx}, 'y', {ry}, 'labels', {rl}, 'colors', {rc})

  → View.RenderWaveform(axesIdx, xCell, yCell, labels, colorList, rightYData)
```

### 8.4 View 渲染

```matlab
hasRightY = isstruct(rightYData) && isfield(rightYData, 'x') && ~isempty(rightYData.x);

if hasRightY
    % 双Y模式
    yyaxis(ax, 'left');
    → 画左Y线（'Tag','leftY', 'LineStyle','-'）
    yyaxis(ax, 'right');
    → 画右Y线（'Tag','rightY', 'LineStyle','--'）循环 rightYData.x
    yyaxis(ax, 'left');  % 固定活动侧
else
    % 普通模式
    → 画全部线（'LineStyle','-'）
end
```

### 8.5 状态同步

每次横轴/右Y轴变更后，Presenter 调用：
```matlab
SyncViewAxisState(axIdx)
  → [xDsIdx, xColIdx] = Session.GetXChannel(axIdx)
  → refs = Session.GetRightYChannel(axIdx)
  → rightYList = cellfun(@(r) [r.DatasetIdx, r.ColIdx], refs, 'Uni', false)
  → View.UpdateAxisChannelState(axIdx, xDsIdx, xColIdx, rightYList)
      → 更新 CurXChannel_, CurRightYChannel_, AxesXChannelMap_
```

### 8.6 通道表标记

`GetChannelState` 在通道勾选时附加标记：
- `[X]`：该通道是当前 axes 的横轴
- `[R]`：该通道在当前 axes 的右Y列表中

仅在通道已勾选（`isChecked=true`）时显示标记。

---

## 九、游标卡尺系统

### 9.0 架构概览

```
鼠标移动 → View.onCursorMotion (WindowButtonMotionFcn)
  → notify('CursorMotion', {axesIdx, x, mouseY})
  → Presenter.OnCursorMotion
    → O(1) 索引推算 (CursorXParams_ 缓存)
    → 索引防抖 (CursorLastIdx_)
    → 智能吸附：min(|yVals - mouseY|) 找最近通道
    → 记录吸附线句柄 (CursorActiveLine_)
    → 构建 markerData → View.UpdateCursorMarkers
    → 构建 readout → UpdateCursorReadout
```

### 9.0.1 O(1) 索引查找

数据均匀时用公式推算，避免 `min(abs(xData - x))` 全量扫描：

```matlab
params = CursorXParams_{axIdx};  % struct('x0','dx','n','isUniform')
if params.isUniform
    idx = round((x - params.x0) / params.dx) + 1;
    idx = max(1, min(params.n, idx));
else
    [~, idx] = min(abs(xData - x));  % 回退
end
```

缓存在 `buildXData` 中构建，数据变化时通过 `InvalidateCursorCache` 失效。

### 9.0.2 Y 向智能吸附

每轴一个红圈 marker，自动吸附到离鼠标 Y 坐标最近的通道：

```matlab
validMask = ~isnan(yVals);
[~, nearestK] = min(abs(yVals(validMask) - d.mouseY));
snapY = yVals(validIdx(nearestK));
```

吸附结果存入 `CursorActiveLine_{axIdx}`，供 `CreateDatatip` 使用。

### 9.0.3 悬浮文本

marker 旁显示坐标，1.5% 偏移避免遮挡：

```matlab
set(hoverTexts{axIdx}, 'Position', [md.x + xOffset, md.y + yOffset], ...
    'String', md.hoverText, 'Visible', 'on');
```

Y 值使用动态工程单位格式化（`formatEngValue`）：自动选择 mm/um/nm/pm。

### 9.0.4 DataTip 集成

两条路径自然共存，无需检测模式状态：

| 状态 | 点击目标 | 行为 |
|------|----------|------|
| DataTip 关闭 | 线条 | `ButtonDownFcn` → `OnAxesButtonDown` → 游标/状态栏 |
| DataTip 关闭 | 空白 | axes `ButtonDownFcn` → `OnAxesButtonDown` → 游标/状态栏 |
| DataTip 开启 | 线条 | MATLAB 模式管理器拦截 → 创建原生 datatip |
| DataTip 开启 | 空白 | 无操作 |

`datacursormode(fig).Enable` 的 `PostSet` 监听用于暂停游标（`DataTipActive_` 标志）：

```matlab
dcm = datacursormode(fig);
addlistener(dcm, 'Enable', 'PostSet', @(~, ~) obj.OnDataCursorEnableChanged());
% 激活 → HideCursor + DataTipActive_=true → OnCursorMotion 直接 return
% 关闭 → DataTipActive_=false → 下次鼠标移动自动恢复
```

右键清除当前 axes 的 datatip：`delete(findall(ax, 'Type', 'datatip'))`。

### 9.0.5 动态工程单位

`formatPrecisionValue(val_mm)` 以 mm 为基准，根据绝对值自动选择单位：

| 范围（mm） | 单位 | 格式 |
| --- | --- | --- |
| ≥ 1 mm | mm | `%.3f mm` |
| ≥ 1e-3 mm | um | `%.3f um` |
| ≥ 1e-6 mm | nm | `%.3f nm` |
| < 1e-6 mm | pm | `%.3f pm` |

应用于：悬浮文本 Y 值、readout 面板 Y 值、datatip `CustomFormatFcn`。

### 9.0.6 悬浮文本偏移

悬浮文本相对于吸附交点偏移 1.5%（X/Y 各取 axes 范围的 1.5%），避免遮挡数据：

```matlab
xl = xlim(ax); yl = ylim(ax);
xOffset = 0.015 * (xl(2) - xl(1));
yOffset = 0.015 * (yl(2) - yl(1));
set(hoverText, 'Position', [md.x + xOffset, md.y + yOffset], ...);
```

---

## 十、RenderWaveform 渲染细节

### 10.1 清除与重置

```matlab
delete(allchild(ax));           % 清除两侧所有线条（yyaxis 安全）
ax.LineStyleOrder = '-';        % 重置线型顺序，避免 yyaxis 残留的圈/三角标记
ax.LineStyleOrderIndex = 1;     % 重置线型循环索引
ax.ColorOrderIndex = 1;         % 重置颜色循环索引
```

### 10.2 颜色分配

使用 `ChannelColorIndex(datasetIdx, colIdx, nColors)` 哈希分配颜色：
```matlab
mod((datasetIdx-1)*7 + colIdx, nColors) + 1
```
保证同一通道在反复勾选/取消时颜色稳定。

### 10.3 线型规则

| 位置 | LineStyle | Tag |
|------|-----------|-----|
| 左Y通道 | `'-'`（实线） | `'leftY'` |
| 右Y通道 | `'--'`（虚线） | `'rightY'` |
| 普通模式（无右Y） | `'-'`（实线） | 无 |

### 10.4 Legend + ButtonDownFcn

- 通道数 ≥ 2：显示 legend（`'Interpreter','none'`, `'Location','northwest'`）
- 通道数 = 1：`legend(ax, 'off')`

**ButtonDownFcn**：每条数据线创建后设置 `h.ButtonDownFcn = @(s,e) obj.OnAxesButtonDown(axesIdx, e)`，与 axes 的 `ButtonDownFcn` 共用同一处理器，确保点击线条也能触发游标/状态栏逻辑。

---

## 十一、ExportFigure 导出逻辑

### 10.1 线条过滤

使用 Tag 过滤左右Y线（避免 `findobj` 返回全部线）：
```matlab
allSrcLines = findobj(ax, 'Type', 'line');
leftSrc = allSrcLines(arrayfun(@(l) strcmp(l.Tag, 'leftY'), allSrcLines));
rightSrc = allSrcLines(arrayfun(@(l) strcmp(l.Tag, 'rightY'), allSrcLines));
hasRightY = ~isempty(rightSrc);
```

兼容旧 figure（无 Tag）：`leftSrc` 和 `rightSrc` 均为空，走普通模式分支。

### 10.2 导出绘制

- 左Y线 → `yyaxis(sub, 'left')` + `plot(sub, ...)`
- 右Y线 → `yyaxis(sub, 'right')` + `plot(sub, ...)`
- legend 使用 subplot 上的 handle（非源 axes handle）
- X 标签格式：`数据集名 / 列名`

### 10.3 源 axes 保护

读取 YLabel 前切换源 axes 活动侧，读取后恢复：
```matlab
yyaxis(ax, 'left');
leftLabel = get(get(ax, 'YLabel'), 'String');
yyaxis(ax, 'right');
rightLabel = get(get(ax, 'YLabel'), 'String');
yyaxis(ax, 'left');  % 恢复
```

### 10.4 弹窗生命周期

```matlab
fig.CloseRequestFcn = @(s, e) obj.RemovePopup(fig);
```
关闭时从 `PopupFigures` 跟踪列表移除并 delete。

---

## 十二、LinkXAxes 链接逻辑

`LinkXAxes` 按X通道引用分组链接，不同自定义横轴的 axes 不互相链接：

```matlab
→ 收集有效 axes 及其 X 通道引用 (AxesXChannelMap_)
→ 按引用 key = sprintf('%d_%d', ref(1), ref(2)) 分组
→ 每组内 linkaxes([grp{:}], 'x')
```

- 默认索引模式：key = `'0_0'`，所有默认X的 axes 链接在一起
- 自定义横轴：相同数据集+列的 axes 链接，不同则独立

---

## 十三、传函分析 (`view/TransferFunctionView.m`)

| # | 操作 | 触发 | 事件 | 载荷 | Presenter 处理 |
|---|------|------|------|------|----------------|
| 27 | Browse 按钮 | 按钮点击 | `BrowseClicked` | 无 | `OnBrowse` → 文件夹选择 → 写回路径 |
| 28 | Import 按钮 | 按钮点击 | `ImportButtonClicked` | 无 | `OnImport` → 导入 → 提取 FRF 曲线 → 渲染 |
| 29 | 曲线表复选框 | CellEdit | `CurveSelectionChanged` | `{row}`（未被使用） | `OnCurveSelection` → `ApplySelection` → 按勾选状态重绘 |
| 30 | Clear All 按钮 | 按钮点击 | `ClearAllClicked` | 无 | `OnClearAll` → 清空曲线 + 重置路径 + 清空图表 |

---

## 十四、未被 Presenter 监听的事件

| 事件 | 原因 |
|------|------|
| `AxesAddClicked` | View 内部完成 axes 创建，无需 Presenter 参与 |
| `LayoutChanged` | View 内部完成布局切换，无需 Presenter 参与 |

---

## 十五、Presenter 调用 View 的方法汇总

| View 方法 | 被哪些 Presenter 方法调用 |
|-----------|--------------------------|
| `GetFocusedAxes()` | OnChannelCheckChanged, OnNormalize, OnSliceDialog, OnSliceReset, OnRenameChannel, OnSetSampleRate, OnAxesClicked, ShowSpectrumPopup, OnSetXAxis, OnClearXAxis, OnSetRightYAxis, OnClearRightYAxis, OnClearPlot, OnClearAll |
| `GetAxesCount()` | OnAxesRemove, OnExportFigure |
| `GetAxes(idx)` | OnExportFigure, ComputeNormParams |
| `ClearAllAxes()` | OnClearAll, OnClearPlot |
| `ClearAxes(idx)` | RenderAxes（空通道时） |
| `RenderWaveform(...)` | RenderAxes |
| `SetChannelTable(rows)` | RefreshChannelTable（14处调用） |
| `UpdateAxisChannelState(...)` | SyncViewAxisState（10处调用） |
| `ShowLoading / CloseLoading` | OnBrowseFolder, OnImportFiles, OnExportDatasetExcel |
| `ShowError / ShowInfo` | 多处验证逻辑 |

---

## 十六、状态栏消息 (`StatusCallback`)

| 位置 | 消息 |
|------|------|
| `AddResultsToSession` | `'  导入 %d 个数据集'` |
| `OnClearAll` | `' '`（清空） |
| `OnAxesClicked`（自定义横轴） | `'  Axes %d  \|  X = %.6g (%s)  \|  Y = %.6g'` |
| `OnAxesClicked`（默认横轴） | `'  Axes %d  \|  X = %.6g  \|  Y = %.6g'` |
| `OnAxesClicked`（无效） | `' '`（清空） |
| `OnSetSampleRate` | `'  %s 采样率 = %g Hz'` |
| `OnSetXAxis` | `'  Axes %d 横轴 → %s / %s'` |
| `OnClearXAxis` | `'  Axes %d 横轴 → 默认'` |

---

## 十七、右键菜单路由逻辑

```
OnContextMenuOpening()           ← 右键时自动选中最近左键点击的行
  ├─ 计算 isXChannel, isRightY
  ├─ 动态启用/禁用横轴、右Y菜单项
  └─ 互斥：同通道不能同时为横轴和右Y

OnContextRename()                ← 重命名（数据集行和通道行均可用）
  ├─ 设置 Renaming_=true, ColumnEditable(2)=true
  └─ 用户编辑后 OnChannelEdit(col==2) 确认/取消

OnContextAction(action)          ← 数据集级操作（父行）
  └─ 'exportExcel'               导出 Excel

OnContextChannelAction(action)   ← 通道级操作（子行）
  ├─ 'setSampleRate'             设置采样频率
  ├─ 'slice'                     设置切片范围
  ├─ 'sliceReset'                切片重置
  ├─ 'setXAxis'                  设为横轴
  ├─ 'clearXAxis'                恢复默认横轴
  ├─ 'setRightY'                 设为右Y轴（追加到列表）
  └─ 'clearRightY'               恢复默认Y轴（清除全部右Y）
```

隐含守卫：`OnContextAction` 跳过子行（`~r.isParent`），`OnContextChannelAction` 跳过父行（`r.isParent`）。

数据集全选/取消：通过点击数据集行复选框实现（`OnChannelEdit` isParent 分支）。

重命名模式：右键→重命名后，`Renaming_=true` 禁用展开/折叠，列2临时可编辑。确认（回车/Tab/点击其他地方）或取消（Escape/名称未变/点击其他行）后恢复。

---

## 十八、Session 状态管理汇总

### 17.1 横轴/右Y轴状态清理时机

| 操作 | 清理 X 引用 | 清理右Y引用 | SyncView | RefreshTable |
|------|------------|------------|----------|-------------|
| 勾选通道 (OnChannelCheckChanged) | — | — | ✅ | ✅ |
| 取消勾选通道 (RemoveChannelFromAxes) | 匹配则清 | 匹配则移除 | ✅ | ✅ |
| 删除数据集 (RemoveDataset) | 匹配则清+索引减1 | 匹配则移除+索引减1 | — | — |
| 清空 axes (ClearAxes) | 清空 | 清空 | — | — |
| 删除 axes (RemoveAxes) | 清空 | 清空 | ✅ | ✅ |
| 清空全部 (ClearAllDatasets) | 清空容器 | 清空容器 | ✅ | ✅ |
| 设为横轴 (OnSetXAxis) | 设置 | — | ✅ | ✅ |
| 恢复默认横轴 (OnClearXAxis) | 清空 | — | ✅ | ✅ |
| 设为右Y (OnSetRightYAxis) | — | 追加 | ✅ | ✅ |
| 恢复默认Y (OnClearRightYAxis) | — | 清空 | ✅ | ✅ |
| 清图 (OnClearPlot) | 清空 | 清空 | ✅ | ✅ |

### 17.2 View 状态同步

`SyncViewAxisState(axIdx)` 将 Session 的横轴/右Y轴状态同步到 View：
- `CurXChannel_`：当前聚焦 axes 的横轴引用 `[dsIdx, colIdx]` 或 `[]`
- `CurRightYChannel_`：当前聚焦 axes 的右Y引用列表 `cell array of [dsIdx, colIdx]`
- `AxesXChannelMap_`：每轴的横轴引用（用于 `LinkXAxes` 分组）

`ClearAllAxes()` 额外清除 View 的 `AxesXChannelMap_`、`CurXChannel_`、`CurRightYChannel_`。
