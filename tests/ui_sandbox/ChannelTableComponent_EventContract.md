# ChannelTableComponent 事件契约与测试矩阵白皮书

> **组件**：`view/components/ChannelTableComponent.m`
> **架构层级**：L2（黑盒组件）
> **对外事件**：`ActionRequested`
> **版本**：V2 MVP

---

## 第一部分：事件字典 (Event Dictionary)

### 1.1 对外事件总线

`ChannelTableComponent` 仅有一个对外事件：

```
Event: ActionRequested
Payload: AppEventData(struct)
```

### 1.2 Action 载荷字典

| # | action 字符串 | 触发源 | 载荷字段 | 说明 |
|---|--------------|--------|---------|------|
| 1 | `checkChanged` | `onCellEdit` — 列1复选框 | `datasetIdx`, `colIdx`, `checked` | `colIdx=0` 表示父行全选/全取消 |
| 2 | `renameDataset` | `onCellEdit` — 列2重命名提交 | `datasetIdx`, `colIdx=0`, `value` | 父行重命名 |
| 3 | `renameChannel` | `onCellEdit` — 列2重命名提交 | `datasetIdx`, `colIdx`, `value` | 子行重命名 |
| 4 | `setSampleRate` | `fire()` — 右键菜单 | `datasetIdx`, `colIdx=0` | 仅父行可用 |
| 5 | `exportExcel` | `fire()` — 右键菜单 | `datasetIdx`, `colIdx` | 父行 `colIdx=0`，子行 `colIdx=0` |
| 6 | `slice` | `fire()` — 右键菜单 | `datasetIdx`, `colIdx` | 仅子行可用 |
| 7 | `sliceReset` | `fire()` — 右键菜单 | `datasetIdx`, `colIdx` | 仅子行可用 |
| 8 | `setXAxis` | `fire()` — 右键菜单 | `datasetIdx`, `colIdx` | 仅子行可用 |
| 9 | `clearXAxis` | `fire()` — 右键菜单 | `datasetIdx=0`, `colIdx=0` | 仅子行可用；Presenter 补注入 `axesIdx` |
| 10 | `setRightY` | `fire()` — 右键菜单 | `datasetIdx`, `colIdx` | 仅子行可用 |
| 11 | `clearRightY` | `fire()` — 右键菜单 | `datasetIdx=0`, `colIdx=0` | 仅子行可用；Presenter 补注入 `axesIdx` |

---

## 第二部分：基于事件载荷的穷举测试矩阵 (Payload-Driven Matrix)

---

### Action 1: `checkChanged`

**触发链路**：`onCellEdit(e)` → `e.Indices(2)==1` → `notify('ActionRequested', ...)`

#### 正向触发 (Happy Path)

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 1.1 | 子行勾选 ON | DS1 展开，ch1 未勾选 | `Data{visRow,1}=true` + `CellEditCallback([visRow,1])` | `action=checkChanged, datasetIdx=1, colIdx=1, checked=true` |
| 1.2 | 子行勾选 OFF | ch1 已勾选 | `Data{visRow,1}=false` + `CellEditCallback([visRow,1])` | `checked=false` |
| 1.3 | 父行勾选（全选） | DS1 未展开，2 个子通道 | `Data{1,1}=true` + `CellEditCallback([1,1])` | 触发 2 个事件：`colIdx=1` 和 `colIdx=2`，均为 `checked=true` |
| 1.4 | 父行取消（全取消） | DS1 父行已勾选 | `Data{1,1}=false` + `CellEditCallback([1,1])` | 2 个事件，`checked=false` |

#### 负向拦截 (Negative/Blocked)

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 1.5 | `Rebuilding=true` 时编辑 | `SetRows` 执行期间 | 直接调用 `CellEditCallback` | 事件**不触发**（`Rebuilding` 守卫） |
| 1.6 | `VisibleRowMap` 为空 | `SetRows({})` 清空后 | `CellEditCallback([1,1])` | 事件**不触发**（空守卫） |
| 1.7 | 编辑列2（非复选框列） | 正常状态 | `CellEditCallback([visRow,2])` | 事件**不触发**（`Indices(2)~=1` 守卫） |
| 1.8 | 行索引越界 | 正常状态 | `CellEditCallback([999,1])` | 事件**不触发**（越界守卫） |
| 1.9 | 行索引为0 | 正常状态 | `CellEditCallback([0,1])` | 事件**不触发**（`visRow<1` 守卫） |

#### 异常载荷 (Edge Payload)

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 1.10 | 单通道父行勾选 | DS 仅有 1 个子通道 | `Data{1,1}=true` + `CellEditCallback([1,1])` | 仅触发 1 个事件，`colIdx=1` |
| 1.11 | 最后一行子行勾选 | 多数据集展开，最后一行 | `Data{last,1}=true` + `CellEditCallback([last,1])` | 正确携带最后一个数据集的 `datasetIdx` 和 `colIdx` |

---

### Action 2: `renameDataset`

**触发链路**：`onContextRename()` → 编辑列2 → `onCellEdit(e)` → `e.Indices(2)==2 && Renaming && r.isParent` → `notifyAction('renameDataset', ...)`

#### 正向触发

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 2.1 | 正常重命名父行 | DS1 父行可见 | 选行 → 重命名菜单 → `Data{1,2}='NewDS'` → `CellEditCallback([1,2])` | `action=renameDataset, datasetIdx=1, colIdx=0, value='NewDS'` |

#### 负向拦截

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 2.2 | 重命名为原名 | 父行 label='DS1' | `Data{1,2}='DS1'` → `CellEditCallback([1,2])` | 事件**不触发**（`newName==RenameOriginal` 守卫） |
| 2.3 | 重命名为空字符串 | 父行可见 | `Data{1,2}='  '` → `CellEditCallback([1,2])` | 事件**不触发**（`isempty(newName)` 守卫），标签回退为原名 |
| 2.4 | 重命名被中途中断 | 开始重命名后 | 点击其他行（`CellSelect`）→ 再 `CellEditCallback([1,2])` | 事件**不触发**（`Renaming` 已被 `CellSelect` 重置） |
| 2.5 | `Renaming=false` 时编辑列2 | 未进入重命名模式 | `Data{1,2}='X'` → `CellEditCallback([1,2])` | 事件**不触发**（`Renaming=false` 守卫） |
| 2.6 | 编辑行与 LastClickedRow 不一致 | 重命名第1行，但 LastClickedRow=2 | `CellEditCallback([1,2])` | 事件**不触发**（`visRow~=LastClickedRow` 守卫） |

#### 异常载荷

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 2.7 | 重命名含前后空格 | 父行可见 | `Data{1,2}='  NewDS  '` → `CellEditCallback([1,2])` | `value='NewDS'`（`strtrim` 生效） |
| 2.8 | 重命名为超长字符串 | 父行可见 | 64 字符字符串 | 事件正常触发，`value` 完整 |

---

### Action 3: `renameChannel`

**触发链路**：与 `renameDataset` 相同，但 `r.isParent==false`

#### 正向触发

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 3.1 | 正常重命名子行 | DS1 展开，ch1 可见 | 选行 → 重命名菜单 → `Data{visRow,2}='new_ch'` → `CellEditCallback` | `action=renameChannel, datasetIdx=1, colIdx=1, value='new_ch'` |

#### 负向拦截

| # | 用例 | 说明 |
|---|------|------|
| 3.2 | 同 2.2–2.6 | 守卫逻辑与 `renameDataset` 完全对称 |

#### 异常载荷

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 3.3 | 重命名最后一个子通道 | 展开后最后一行 | 同操作 | `colIdx` 为该数据集的最后一列 |

---

### Action 4: `setSampleRate`

**触发链路**：`fire('setSampleRate')` → `r.isParent` 分支 → `notifyAction('setSampleRate', dsIdx, 0, [])`

#### 正向触发

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 4.1 | 父行设置采样率 | 选中 DS2 父行 | 菜单 `设置采样频率...` | `action=setSampleRate, datasetIdx=2, colIdx=0` |

#### 负向拦截

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 4.2 | 子行不可用 | 选中通道行 | 菜单 `Enable=off` | 事件**不触发**（菜单 disabled） |
| 4.3 | 子行强行 `fire` | 子行被选中 | `fire('setSampleRate')` | 进入 `r.isParent` 分支但 `r.isParent=false` → 走 default → 不匹配 → **不触发** |

#### 异常载荷

| # | 用例 | 断言 |
|---|------|------|
| 4.4 | 仅有一个数据集 | `datasetIdx=1, colIdx=0` |

---

### Action 5: `exportExcel`

**触发链路**：`fire('exportExcel')` → 父行: `notifyAction(dsIdx, 0, [])` / 子行: switch 中 `notifyAction(dsIdx, 0, [])`

#### 正向触发

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 5.1 | 父行导出 | 选中 DS1 父行 | 菜单 `导出 Excel` | `action=exportExcel, datasetIdx=1, colIdx=0` |
| 5.2 | 子行导出 | 选中通道行 | 菜单 `导出 Excel` | `action=exportExcel, datasetIdx=对应ds, colIdx=0` |

#### 负向拦截

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 5.3 | `getVisibleRow` 返回空 | `VisibleRowMap` 为空 | `fire('exportExcel')` | 事件**不触发** |

#### 异常载荷

| # | 用例 | 断言 |
|---|------|------|
| 5.4 | 多数据集最后一行 | `datasetIdx` 为最大值 |

---

### Action 6: `slice`

**触发链路**：`fire('slice')` → 子行分支 → `notifyAction(dsIdx, colIdx, [])`

#### 正向触发

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 6.1 | 子行设置切片 | 选中通道行 | 菜单 `设置切片范围...` | `action=slice, datasetIdx=1, colIdx=1` |

#### 负向拦截

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 6.2 | 父行不可用 | 选中父行 | 菜单 `Enable=off` | 事件**不触发** |
| 6.3 | `getVisibleRow` 返回空 | `VisibleRowMap` 为空 | `fire('slice')` | 事件**不触发** |

#### 异常载荷

| # | 用例 | 断言 |
|---|------|------|
| 6.4 | 最后一个数据集的最后一个通道 | `datasetIdx` 和 `colIdx` 均为最大值 |

---

### Action 7: `sliceReset`

与 `slice` 完全对称，`action=sliceReset`。触发链路、正向/负向/边界条件相同。

| # | 用例 | 断言 |
|---|------|------|
| 7.1 | 正常重置 | `action=sliceReset, datasetIdx=1, colIdx=1` |
| 7.2 | 父行不可用 | 事件**不触发** |
| 7.3 | `getVisibleRow` 返回空 | 事件**不触发** |

---

### Action 8: `setXAxis`

**触发链路**：`fire('setXAxis')` → 子行分支 → `notifyAction(dsIdx, colIdx, [])`

#### 正向触发

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 8.1 | 子行设为横轴 | 选中通道行，无 X 轴绑定 | 菜单 `设为横轴` | `action=setXAxis, datasetIdx=1, colIdx=1` |

#### 负向拦截

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 8.2 | 父行不可用 | 选中父行 | 菜单 `Enable=off` | 事件**不触发** |
| 8.3 | 已是 X 轴通道 | `UpdateXChannel(1,1)`, 选中 ch1 | 菜单 `Enable=off` | 事件**不触发**（`isXChannel=true`） |

#### 异常载荷

| # | 用例 | 断言 |
|---|------|------|
| 8.4 | 仅有一个通道 | `datasetIdx=1, colIdx=1` |

---

### Action 9: `clearXAxis`

**触发链路**：`fire('clearXAxis')` → 子行分支 → `notifyAction(0, 0, [])`

#### 正向触发

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 9.1 | 清除 X 轴 | `UpdateXChannel(1,1)`, 选中 ch1 | 菜单 `恢复默认横轴` | `action=clearXAxis, datasetIdx=0, colIdx=0` |

#### 负向拦截

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 9.2 | 非 X 轴通道 | 无 X 轴绑定，选中 ch1 | 菜单 `Enable=off` | 事件**不触发** |
| 9.3 | 父行 | 选中父行 | 菜单 `Enable=off` | 事件**不触发** |

#### 异常载荷

| # | 用例 | 断言 |
|---|------|------|
| 9.4 | 载荷固定为 `0,0` | 始终 `datasetIdx=0, colIdx=0`，由 Presenter 补注入 `axesIdx` |

---

### Action 10: `setRightY`

**触发链路**：`fire('setRightY')` → 子行分支 → `notifyAction(dsIdx, colIdx, [])`

#### 正向触发

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 10.1 | 子行设为右Y | 选中通道行，无右Y绑定 | 菜单 `设为右 Y 轴` | `action=setRightY, datasetIdx=1, colIdx=1` |

#### 负向拦截

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 10.2 | 父行不可用 | 选中父行 | 菜单 `Enable=off` | 事件**不触发** |
| 10.3 | 已是右Y通道 | `UpdateRightY({[1,1]})`, 选中 ch1 | 菜单 `Enable=off` | 事件**不触发** |
| 10.4 | 已是 X 轴通道 | `UpdateXChannel(1,1)`, 选中 ch1 | 菜单 `Enable=off` | 事件**不触发** |

#### 异常载荷

| # | 用例 | 断言 |
|---|------|------|
| 10.5 | 多右Y场景 | 已绑定 ch1 为右Y，选中 ch2 → `colIdx=2` |

---

### Action 11: `clearRightY`

**触发链路**：`fire('clearRightY')` → 子行分支 → `notifyAction(0, 0, [])`

#### 正向触发

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 11.1 | 清除右Y | `UpdateRightY({[1,2]})`, 选中 ch2 | 菜单 `恢复默认 Y 轴` | `action=clearRightY, datasetIdx=0, colIdx=0` |

#### 负向拦截

| # | 用例 | 前置状态 | 操作 | 断言 |
|---|------|---------|------|------|
| 11.2 | 非右Y通道 | 无右Y绑定，选中 ch1 | 菜单 `Enable=off` | 事件**不触发** |
| 11.3 | 父行 | 选中父行 | 菜单 `Enable=off` | 事件**不触发** |

#### 异常载荷

| # | 用例 | 断言 |
|---|------|------|
| 11.4 | 多右Y中清除 | 绑定 ch1+ch2 为右Y，选中 ch1 → 仅触发1次 |

---

## 横切关注点 (Cross-Cutting Concerns)

| # | 维度 | 测试用例 | 说明 |
|---|------|---------|------|
| X1 | `rebuildData` 空 rows | `SetRows(struct([]))` | `ChannelRows` 为空 → `VisibleRowMap=[]`，表格行数=0 |
| X2 | `rebuildData` datasetName 为空 | 构造 `datasetName=''` 的父行 | `names{end+1} = r.label`（回退到 label） |
| X3 | 标签以 `/` 开头 | 子行 label='/ch1' | `shortLabel = strtrim(extractAfter('/ch1', 1))` → `'ch1'` |
| X4 | `ExpandCollapse` 状态保持 | 展开后 `SetRows` 新数据 | `ExpandedSets` 按 `datasetIdx` 索引，新数据的同名 DS 保持展开 |
| X5 | `UpdateXChannel` 清除 | `UpdateXChannel([])` | `CurXChannel=[]`，所有菜单互斥规则重置 |
| X6 | `UpdateRightY` 清除 | `UpdateRightY({})` | `CurRightYList={}`，所有右Y菜单重置 |
| X7 | 多右Y互斥 | ch1=右Y, ch2=右Y | `isInRightYList` 遍历全部，两个通道均可触发 `clearRightY` |
| X8 | X 与右Y 同时绑定 | ch1=X, ch2=右Y | `setXAxis` 对 ch2 仍 enabled；`setRightY` 对 ch1 disabled |

---

## 互斥规则完整真值表

| 行类型 | isXChannel | isRightY | setXAxis | clearXAxis | setRightY | clearRightY | setSampleRate | slice / sliceReset |
|--------|-----------|----------|----------|------------|-----------|-------------|---------------|-------------------|
| 父行 | — | — | OFF | OFF | OFF | OFF | **ON** | OFF |
| 子行 | F | F | **ON** | OFF | **ON** | OFF | OFF | **ON** |
| 子行 | T | F | OFF | **ON** | OFF | OFF | OFF | **ON** |
| 子行 | F | T | **ON** | OFF | OFF | **ON** | OFF | **ON** |
| 子行 | T | T | OFF | **ON** | OFF | **ON** | OFF | **ON** |

---

## 统计摘要

| 维度 | 数量 |
|------|------|
| 对外事件 | 1 (`ActionRequested`) |
| Action 类型 | 11 |
| Happy Path 用例 | 16 |
| Negative 用例 | 22 |
| Edge 用例 | 9 |
| 横切关注点 | 8 |
| **理论用例总计** | **55** |
