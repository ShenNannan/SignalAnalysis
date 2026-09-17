% StartApp - 运动台数据分析工具入口
%
% 设置路径并启动统一窗口（时域分析/传函分析页签）。
% app 句柄保留在 base 工作区，便于命令行调试。
% 注意：不使用 genpath 以避免将 tests/ 等目录加入路径。

thisDir = fileparts(mfilename('fullpath'));
dirs = {'', 'app', 'view', 'view/components', 'presenter', 'model', 'service'};
for k = 1:numel(dirs)
    addpath(fullfile(thisDir, dirs{k}));
end
rehash;

app = SignalAnalysisApp(); %#ok<NASGU>
