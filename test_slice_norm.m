%% test_slice_norm.m — 验证通道切片 + 归一化功能
%  使用 DRFDOT/Trace_data 作为测试数据

clear; clc;
addpath(genpath(fileparts(mfilename('fullpath'))));

%% 1. 数据导入
rootDir = fullfile(fileparts(mfilename('fullpath')), 'DRFDOT', 'Trace_data');
fprintf('导入目录: %s\n', rootDir);

results = DataReaderFactory.BatchImportFolder(rootDir);
fprintf('导入结果: %d 个数据集\n', length(results));

if isempty(results)
    error('未找到可导入的数据');
end

%% 2. 加载数据集
ds = DataReaderFactory.LoadStandard(results(1).matPath);
fprintf('数据集: %d 行 x %d 列\n', ds.RowCount, ds.ColumnCount);
fprintf('列名: %s\n', strjoin(ds.ColumnNames, ', '));

%% 3. 创建 SessionData
session = SessionData(6);
session.AddDataset(ds, results(1).name, results(1).matPath);

%% 4. 添加通道到 axes 1
session.AddChannelToAxes(1, 1, 1);
session.AddChannelToAxes(1, 1, 2);
chans = session.GetAxesChannels(1);
fprintf('通道数: %d\n', length(chans));

%% 5. 验证切片
fprintf('\n--- 切片测试 ---\n');
chan1 = chans{1};
fprintf('通道1 原始切片: [%d, %d], 数据长度: %d\n', ...
    chan1.SliceRange(1), chan1.SliceRange(2), length(chan1.Data));

% 设置切片 100~500
session.SetChannelSlice(1, 1, 100, 500);
chan1 = session.GetChannel(1, 1);
fprintf('通道1 设置后切片: [%d, %d]\n', chan1.SliceRange(1), chan1.SliceRange(2));

assert(chan1.SliceRange(1) == 100, '切片起始错误');
assert(chan1.SliceRange(2) == 500, '切片结束错误');
fprintf('切片设置: OK\n');

% 重置切片
session.SetChannelSlice(1, 1, 1, length(chan1.Data));
chan1 = session.GetChannel(1, 1);
assert(chan1.SliceRange(1) == 1 && chan1.SliceRange(2) == length(chan1.Data), '切片重置失败');
fprintf('切片重置: OK\n');

%% 6. 验证归一化模式
fprintf('\n--- 归一化模式测试 ---\n');
assert(strcmp(session.GetAxesNormMode(1), 'none'), '默认归一化应为 none');

session.SetAxesNormMode(1, 'minmax');
assert(strcmp(session.GetAxesNormMode(1), 'minmax'), '归一化模式设置失败');

session.SetAxesNormMode(1, 'zscore');
assert(strcmp(session.GetAxesNormMode(1), 'zscore'), '归一化模式切换失败');

session.SetAxesNormMode(1, 'none');
assert(strcmp(session.GetAxesNormMode(1), 'none'), '归一化模式重置失败');
fprintf('归一化模式: OK\n');

%% 7. 验证 NormalizeAxes（需要 figure）
fprintf('\n--- NormalizeAxes 测试 ---\n');
fig = figure('Visible', 'off');
ax = axes('Parent', fig);
plotCtrl = PlotController(fig, 6, fig);
idx = plotCtrl.AddAxes();

% 绘制原始数据
chan1 = session.GetChannel(1, 1);
sig = chan1.Data(1:500);
plotCtrl.PlotTimeSeries(1, (1:500)', sig, 'DisplayName', 'test', 'Color', 'b');

% 执行归一化
plotCtrl.NormalizeAxes(1, 'minmax', session);
lines = findobj(plotCtrl.GetAxesHandle(1), 'Type', 'line');
yData = get(lines(1), 'YData');
fprintf('Min-Max 归一化后: min=%.4f, max=%.4f\n', min(yData), max(yData));

assert(min(yData) >= -0.01, 'Min-Max 最小值异常');
assert(max(yData) <= 1.01, 'Min-Max 最大值异常');
fprintf('Min-Max 归一化: OK\n');

% Z-Score
delete(lines);
plotCtrl.PlotTimeSeries(1, (1:500)', sig, 'DisplayName', 'test', 'Color', 'b');
plotCtrl.NormalizeAxes(1, 'zscore', session);
lines = findobj(plotCtrl.GetAxesHandle(1), 'Type', 'line');
yData = get(lines(1), 'YData');
fprintf('Z-Score 归一化后: mean=%.4f, std=%.4f\n', mean(yData), std(yData));
assert(abs(mean(yData)) < 0.01, 'Z-Score 均值异常');
fprintf('Z-Score 归一化: OK\n');

% Mean Zero
delete(lines);
plotCtrl.PlotTimeSeries(1, (1:500)', sig, 'DisplayName', 'test', 'Color', 'b');
plotCtrl.NormalizeAxes(1, 'meanzero', session);
lines = findobj(plotCtrl.GetAxesHandle(1), 'Type', 'line');
yData = get(lines(1), 'YData');
fprintf('Mean Zero 归一化后: mean=%.6f\n', mean(yData));
assert(abs(mean(yData)) < 0.01, 'Mean Zero 均值异常');
fprintf('Mean Zero 归一化: OK\n');

close(fig);

%% 8. 验证 AnalysisEngine 切片应用
fprintf('\n--- AnalysisEngine 切片集成测试 ---\n');
fig2 = figure('Visible', 'off');
plotCtrl2 = PlotController(fig2, 6, fig2);
plotCtrl2.AddAxes();
engine = AnalysisEngine(session, plotCtrl2);

% 设置切片
session.SetChannelSlice(1, 1, 100, 300);
session.SetChannelSlice(1, 2, 200, 400);

engine.RunAnalysis(1, 'time');
lines = findobj(plotCtrl2.GetAxesHandle(1), 'Type', 'line');
fprintf('绘制了 %d 条线\n', length(lines));

% 检查线的 X 范围
for i = 1:length(lines)
    xData = get(lines(i), 'XData');
    fprintf('线 %d: X 范围 [%d, %d], 数据点 %d\n', i, min(xData), max(xData), length(xData));
end
fprintf('AnalysisEngine 切片集成: OK\n');

close(fig2);

fprintf('\n=== 全部测试通过 ===\n');
