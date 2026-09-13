% StartApp - 运动台数据分析工具入口
%
% 设置路径并启动统一窗口（时域分析/传函分析页签）。
% app 句柄保留在 base 工作区，便于命令行调试。

thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(thisDir));
rehash;

app = SignalAnalysisApp(); %#ok<NASGU>
