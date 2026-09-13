classdef PlotController < handle
% PlotController - 统一绘图控制
%
% 支持动态 axes 数量，所有 PlotXxx 方法透传给底层 plot/semilogx。
% 交互功能使用 MATLAB 官方工具：datacursormode、zoom、pan、linkaxes。

    properties (SetAccess = private)
        ParentFigure    % Figure handle
        AxesContainer   % axes 所在的容器（uipanel 或 figure）
        AxesHandles_    cell    % axes handles
        AxesCount_      double  % 当前 axes 数量
        MaxAxes_        double  % axes 数量上限
        LayoutMode_     char    % 当前布局模式
        StatusBar_              % 状态栏 text handle
    end

    methods
        function obj = PlotController(parentFigure, maxAxes, axesContainer)
        % PlotController 构造函数
        %
        % 输入：
        %   parentFigure  - Figure handle
        %   maxAxes       - int 最大 axes 数量，默认 6
        %   axesContainer - axes 所在容器（uipanel），可选

            if nargin < 2
                maxAxes = 6;
            end
            if nargin < 3
                axesContainer = parentFigure;
            end
            obj.ParentFigure = parentFigure;
            obj.AxesContainer = axesContainer;
            obj.MaxAxes_ = maxAxes;
            obj.AxesCount_ = 0;
            obj.AxesHandles_ = {};
            obj.LayoutMode_ = 'single';
            obj.StatusBar_ = [];
        end

        function idx = AddAxes(obj, buttonDownFcn)
        % AddAxes 新增 axes，返回索引
        %
        % 输入：
        %   buttonDownFcn - axes ButtonDownFcn 回调，可选

            if nargin < 2
                buttonDownFcn = [];
            end

            if obj.AxesCount_ >= obj.MaxAxes_
                error('SignalAnalysis:PlotController:AxesLimitReached', ...
                    'Maximum axes count (%d) reached', obj.MaxAxes_);
            end

            obj.AxesCount_ = obj.AxesCount_ + 1;
            idx = obj.AxesCount_;

            % 创建 axes 在容器内
            ax = axes('Parent', obj.AxesContainer, 'Visible', 'on');

            % 官方 axes 工具栏（放大/缩小/平移/数据提示/还原视图）
            axtoolbar(ax, {'zoomin', 'zoomout', 'pan', 'datacursor', 'restoreview'});

            % 设置 axes 点击回调（选中 axes）
            if ~isempty(buttonDownFcn)
                set(ax, 'ButtonDownFcn', buttonDownFcn);
            end

            % 扩展 handles
            while length(obj.AxesHandles_) < idx
                obj.AxesHandles_{end+1} = []; %#ok<AGROW>
            end
            obj.AxesHandles_{idx} = ax;

            % 重新布局
            obj.Relayout(obj.LayoutMode_);

            % 同步 X 轴
            obj.LinkAllAxes();
        end

        function RemoveAxes(obj, axesIdx)
        % RemoveAxes 删除 axes

            if axesIdx < 1 || axesIdx > obj.AxesCount_
                return;
            end

            % 删除 axes handle
            if axesIdx <= length(obj.AxesHandles_) && ~isempty(obj.AxesHandles_{axesIdx})
                delete(obj.AxesHandles_{axesIdx});
            end
            obj.AxesHandles_(axesIdx) = [];
            obj.AxesCount_ = obj.AxesCount_ - 1;

            % 重新布局
            if obj.AxesCount_ > 0
                obj.Relayout(obj.LayoutMode_);
                obj.LinkAllAxes();
            end
        end

        function LinkAllAxes(obj)
        % LinkAllAxes 同步有数据的 axes 的 X 轴（缩放/平移联动）
        % 只链接包含 line 对象的 axes，避免空 axes 混淆轴范围

            handles = {};
            for i = 1:obj.AxesCount_
                ax = obj.AxesHandles_{i};
                if ~isempty(ax) && isvalid(ax)
                    lines = findobj(ax, 'Type', 'line');
                    if ~isempty(lines)
                        handles{end+1} = ax; %#ok<AGROW>
                    end
                end
            end
            if length(handles) >= 2
                linkaxes([handles{:}], 'x');
            end
        end

        function count = GetAxesCount(obj)
        % GetAxesCount 当前 axes 数量

            count = obj.AxesCount_;
        end

        function ax = GetAxesHandle(obj, axesIdx)
        % GetAxesHandle 获取 axes handle

            if axesIdx >= 1 && axesIdx <= length(obj.AxesHandles_)
                ax = obj.AxesHandles_{axesIdx};
            else
                ax = [];
            end
        end

        function PlotTimeSeries(obj, axesIdx, time, signal, varargin)
        % PlotTimeSeries 时域波形
        %
        % 输入：
        %   axesIdx - int axes 索引
        %   time    - [N×1 double] 时间轴
        %   signal  - [N×1 double] 信号
        %   varargin - 透传给 plot()

            ax = obj.GetAxesHandle(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end

            plot(ax, time, signal, varargin{:});
            ylabel(ax, 'Amplitude');
            grid(ax, 'on');
            % xlabel 由 Relayout 统一管理（仅底部 axes 显示）
            obj.Relayout(obj.LayoutMode_);
        end

        function ClearAxes(obj, axesIdx)
        % ClearAxes 清除指定 axes（含关联 legend）

            ax = obj.GetAxesHandle(axesIdx);
            if ~isempty(ax) && isvalid(ax)
                % legend 是 AxesContainer 的子对象，不是 axes 的子对象
                allLegs = findobj(obj.AxesContainer, 'Type', 'legend');
                for k = 1:length(allLegs)
                    if isequal(get(allLegs(k), 'Axes'), ax)
                        delete(allLegs(k));
                    end
                end
                cla(ax);
            end
        end

        function ClearAll(obj)
        % ClearAll 清除全部 axes

            for i = 1:obj.AxesCount_
                obj.ClearAxes(i);
            end
        end

        function fig = ExportToFigure(obj, axesIndices)
        % ExportToFigure 导出指定 axes 到独立 figure

            fig = figure();
            n = length(axesIndices);
            for i = 1:n
                srcAx = obj.GetAxesHandle(axesIndices(i));
                if ~isempty(srcAx) && isvalid(srcAx)
                    ax = subplot(n, 1, i, 'Parent', fig);
                    copyobj(allchild(srcAx), ax);
                    ylabel(ax, get(get(srcAx, 'YLabel'), 'String'));
                    title(ax, get(get(srcAx, 'Title'), 'String'));
                    grid(ax, 'on');
                    if i == n
                        xlabel(ax, 'Sample Index');
                    end
                end
            end
            % 启用 datacursormode 和 axes 工具栏
            dcm = datacursormode(fig);
            set(dcm, 'SnapToDataVertex', 'on', 'Enable', 'on');
            set(dcm, 'UpdateFcn', @obj.FormatDataTip);
        end

        function NormalizeAxes(obj, axesIdx, normMode, normParams)
        % NormalizeAxes 对 axes 上所有通道做纵轴归一化（使用预计算参数）
        %
        % 输入：
        %   axesIdx   - axes 索引
        %   normMode  - 'none'|'minmax'|'zscore'|'meanzero'
        %   normParams - struct，含 channelStats {1xN cell}，每项含 minY/maxY/meanY/stdY

            ax = obj.GetAxesHandle(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end
            if strcmpi(normMode, 'none')
                return;
            end
            if ~isfield(normParams, 'channelStats') || isempty(normParams.channelStats)
                return;
            end

            % 获取 axes 上所有 line 对象
            lines = findobj(ax, 'Type', 'line');
            if isempty(lines), return; end
            lines = flipud(lines);

            nApply = min(length(lines), length(normParams.channelStats));
            for i = 1:nApply
                stats = normParams.channelStats{i};
                yData = get(lines(i), 'YData');
                if isempty(yData), continue; end

                switch lower(normMode)
                    case 'minmax'
                        if stats.maxY - stats.minY > 0
                            yData = (yData - stats.minY) / (stats.maxY - stats.minY);
                        end
                    case 'zscore'
                        if stats.stdY > 0
                            yData = (yData - stats.meanY) / stats.stdY;
                        end
                    case 'meanzero'
                        yData = yData - stats.meanY;
                end

                set(lines(i), 'YData', yData);
            end
        end

        function SetupDataCursor(obj)
        % SetupDataCursor 初始化 MATLAB 内置 datacursormode
        % 自动处理点击创建 datatip、吸附数据点、拖拽、缩放联动

            dcm = datacursormode(obj.ParentFigure);
            set(dcm, 'SnapToDataVertex', 'on', 'Enable', 'off');
            set(dcm, 'UpdateFcn', @obj.FormatDataTip);
        end

        function txt = FormatDataTip(~, ~, event)
        % FormatDataTip 自定义数据提示显示格式

            pos = event.Position;
            txt = sprintf('X = %.6g\nY = %.6g', pos(1), pos(2));
        end

        function InitStatusBar(obj)
        % InitStatusBar 在 figure 底部创建状态栏文本

            obj.StatusBar_ = uicontrol(obj.ParentFigure, ...
                'Style', 'text', ...
                'Units', 'normalized', ...
                'Position', [0, 0, 1, 0.03], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 9, ...
                'String', ' ', ...
                'Enable', 'inactive', ...
                'BackgroundColor', [0.94 0.94 0.94]);
        end

        function UpdateStatusBar(obj, xVal, yVal, axesIdx)
        % UpdateStatusBar 更新状态栏显示坐标

            if isempty(obj.StatusBar_) || ~isvalid(obj.StatusBar_), return; end
            if nargin < 4, axesIdx = 0; end

            if axesIdx > 0
                txt = sprintf('  Axes %d  |  X = %.6g  |  Y = %.6g', axesIdx, xVal, yVal);
            else
                txt = ' ';
            end
            set(obj.StatusBar_, 'String', txt);
        end

        function ClearStatusBar(obj)
        % ClearStatusBar 清空状态栏

            if ~isempty(obj.StatusBar_) && isvalid(obj.StatusBar_)
                set(obj.StatusBar_, 'String', ' ');
            end
        end

        function Relayout(obj, mode)
        % Relayout 布局切换
        %
        % 模式：'single' | 'dual'
        % 使用手动 Position 定位，兼容 uipanel 容器

            obj.LayoutMode_ = mode;

            n = obj.AxesCount_;
            if n == 0
                return;
            end

            % 确定行列数
            switch lower(mode)
                case 'dual'
                    nRows = ceil(n / 2); nCols = 2;
                otherwise
                    nRows = n; nCols = 1;
            end

            % 手动计算每个 axes 的位置（归一化坐标）
            marginX = 0.05;
            marginY = 0.09;
            gapX = 0.02;
            gapY = 0.04;

            totalW = 1 - 2*marginX - (nCols-1)*gapX;
            totalH = 1 - 2*marginY - (nRows-1)*gapY;
            axW = totalW / nCols;
            axH = totalH / nRows;

            lastRow = floor((n-1) / nCols);  % 最后一行的行号

            for i = 1:n
                ax = obj.AxesHandles_{i};
                if ~isempty(ax) && isvalid(ax)
                    col = mod(i-1, nCols);
                    row = floor((i-1) / nCols);

                    posX = marginX + col * (axW + gapX);
                    posY = 1 - marginY - (row+1)*axH - row*gapY;

                    set(ax, 'Units', 'normalized', ...
                        'Position', [posX, posY, axW, axH]);

                    % 只在最底部行显示 xlabel
                    if row == lastRow
                        xlabel(ax, 'Sample Index');
                    else
                        xlabel(ax, '');
                    end
                end
            end
        end
    end
end
