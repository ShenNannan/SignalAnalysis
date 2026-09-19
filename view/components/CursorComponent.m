classdef CursorComponent < handle
%CURSORCOMPONENT  Data-agnostic universal cursor with snap-to-line.
%   Owns an xline, snap marker, and hover text on a single uiaxes.
%   Uses findobj to discover lines at runtime - never caches plot data.
%   Handles both linear and log XScale transparently.
%
%   Properties:
%     LabelFormatterFcn - @(snapY) -> string, external formatting
%
%   Events:
%     CursorSnapped - struct('action','CursorSnapped',
%                           'axesIdx',  N,
%                           'x',        snappedX,
%                           'y',        snappedY,
%                           'lineTag',  'leftY'|'rightY'|'',
%                           'xDataIdx', idx)

    properties
        LabelFormatterFcn   function_handle = @(x, y) sprintf('X: %d\nY: %.6g', round(x), y)
    end

    properties (SetAccess = private)
        AxesIdx            double = 0
    end

    events
        CursorSnapped
    end

    properties (Access = private)
        AxesH              % the uiaxes this cursor lives on
        XLineH             % xline handle (vertical indicator)
        MarkerH            % line handle (snap circle)
        HoverTextH         % text handle (readout label)
        IsUpdating logical = false   % reentrancy guard
        LastSnappedX       double = NaN   % motion debounce X
        LastSnappedY       double = NaN   % motion debounce Y
        LastMouseYData     double = NaN   % mouse Y for multi-line snap
        ActiveLineH                 = []   % currently attached line handle (sticky)
    end

    properties (Constant, Access = private)
        CURSOR_COLOR   = [0.85 0.32 0.09]
        SNAP_RADIUS_PX = 30   % max snap distance in pixels
        HOVER_OFFSET_PX = 12  % fixed pixel offset for hover text
        LINE_SWITCH_THRESHOLD = 0.3  % normalized Y distance to switch lines
    end

    methods
        function obj = CursorComponent(ax, axesIdx)
        %CURSORCOMPONENT  Attach cursor visuals to a uiaxes.
        %   obj = CursorComponent(ax, axesIdx)
        %   ax must already be placed in a layout (so XLim is valid).

            arguments
                ax       (1,1) matlab.graphics.axis.Axes
                axesIdx  (1,1) double {mustBePositive, mustBeInteger}
            end

            obj.AxesH    = ax;
            obj.AxesIdx  = axesIdx;

            % Create xline (hidden until first snap)
            obj.XLineH = xline(ax, 0, ...
                'Color',            obj.CURSOR_COLOR, ...
                'LineWidth',        1.2, ...
                'LineStyle',        '-', ...
                'HitTest',          'off', ...
                'PickableParts',    'none', ...
                'Tag',              'cursor', ...
                'Visible',          'off', ...
                'HandleVisibility', 'off');

            % Snap marker (circle)
            obj.MarkerH = line(ax, NaN, NaN, ...
                'Marker',           'o', ...
                'MarkerSize',       6, ...
                'MarkerFaceColor',  obj.CURSOR_COLOR, ...
                'MarkerEdgeColor',  'w', ...
                'LineStyle',        'none', ...
                'HitTest',          'off', ...
                'PickableParts',    'none', ...
                'Tag',              'cursor', ...
                'XLimInclude',      'off', ...
                'YLimInclude',      'off', ...
                'Visible',          'off', ...
                'HandleVisibility', 'off');

            % Hover text
            obj.HoverTextH = text(ax, 0, 0, '', ...
                'BackgroundColor',      [1 1 1 0.85], ...
                'EdgeColor',            [0.5 0.5 0.5], ...
                'Margin',               4, ...
                'FontSize',             9, ...
                'HitTest',              'off', ...
                'PickableParts',        'none', ...
                'Tag',                  'cursor', ...
                'VerticalAlignment',    'bottom', ...
                'Visible',              'off', ...
                'HandleVisibility',     'off');
        end

        function SetAxesIdx(obj, newIdx)
        %SETAXESIDX  Update the axes index (call after grid re-indexing).
            obj.AxesIdx = newIdx;
        end

        function SetPosition(obj, dataX)
        %SETPOSITION  Programmatically snap cursor to a data-space X value.
        %   Bypasses pixel distance threshold — always finds nearest point.
        %   Used for cross-axis cursor synchronization.

            if obj.IsUpdating, return; end
            if ~isvalid(obj.AxesH), return; end
            if ~obj.hasValidVisuals(), return; end

            obj.IsUpdating = true;
            cleanupObj = onCleanup(@() obj.unlock());  %#ok<NASGU>

            obj.snapAndDisplay(dataX, true);
        end

        function UpdateFromMouse(obj)
        %UPDATEFROMMOUSE  Drive cursor using native ax.CurrentPoint.
        %   Caller (L3 View) has already confirmed mouse is in inner area
        %   via getpixelposition hit-test. Here we trust ax.CurrentPoint
        %   for the inverse matrix projection to data space.

            if obj.IsUpdating, return; end
            if ~isvalid(obj.AxesH), return; end
            if ~obj.hasValidVisuals(), return; end

            obj.IsUpdating = true;
            cleanupObj = onCleanup(@() obj.unlock());  %#ok<NASGU>

            cp = obj.AxesH.CurrentPoint;
            targetX = cp(1, 1);
            obj.LastMouseYData = cp(1, 2);

            % Debounce: same X → skip
            if ~isnan(obj.LastSnappedX) && targetX == obj.LastSnappedX
                return
            end

            obj.snapAndDisplay(targetX, false);
        end

        function Hide(obj)
        %HIDE  Manually hide all cursor visuals.
            obj.hideAll();
            obj.LastSnappedX = NaN;
            obj.LastSnappedY = NaN;
        end

        function RebuildOnAxes(obj)
        %REBUILDONAXES  Re-create cursor objects after cla().
        %   Call after the owning axes has been cleared.
        %   No try-catch: errors propagate to caller for proper handling.
            ax = obj.AxesH;
            if ~isvalid(ax), return; end

            % Destroy stale handles to prevent ghost layers
            if ~isempty(obj.XLineH)    && isvalid(obj.XLineH),    delete(obj.XLineH);    end
            if ~isempty(obj.MarkerH)   && isvalid(obj.MarkerH),   delete(obj.MarkerH);   end
            if ~isempty(obj.HoverTextH) && isvalid(obj.HoverTextH), delete(obj.HoverTextH); end

            obj.XLineH = xline(ax, 0, ...
                'Color', obj.CURSOR_COLOR, 'LineWidth', 1.2, ...
                'LineStyle', '-', 'HitTest', 'off', ...
                'PickableParts', 'none', 'Tag', 'cursor', ...
                'Visible', 'off', 'HandleVisibility', 'off');

            obj.MarkerH = line(ax, NaN, NaN, ...
                'Marker', 'o', 'MarkerSize', 6, ...
                'MarkerFaceColor', obj.CURSOR_COLOR, ...
                'MarkerEdgeColor', 'w', 'LineStyle', 'none', ...
                'HitTest', 'off', 'PickableParts', 'none', ...
                'Tag', 'cursor', 'XLimInclude', 'off', ...
                'YLimInclude', 'off', 'Visible', 'off', ...
                'HandleVisibility', 'off');

            obj.HoverTextH = text(ax, 0, 0, '', ...
                'BackgroundColor', [1 1 1 0.85], ...
                'EdgeColor', [0.5 0.5 0.5], 'Margin', 4, ...
                'FontSize', 9, 'HitTest', 'off', ...
                'PickableParts', 'none', 'Tag', 'cursor', ...
                'VerticalAlignment', 'bottom', 'Visible', 'off', ...
                'HandleVisibility', 'off');
        end
    end

    % ------------------------------------------------------------------
    % Private helpers
    % ------------------------------------------------------------------
    methods (Access = private)

        function unlock(obj)
            obj.IsUpdating = false;
        end

        function tf = hasValidVisuals(obj)
        %HASVALIDVISUALS  Fast check: all 3 graphic handles still alive.
        %   Used as fail-fast guard in SetPosition / UpdateFromMouse / snapAndDisplay.
            tf = ~isempty(obj.MarkerH)   && isvalid(obj.MarkerH)   ...
              && ~isempty(obj.XLineH)    && isvalid(obj.XLineH)    ...
              && ~isempty(obj.HoverTextH) && isvalid(obj.HoverTextH);
        end

        function hideAll(obj)
            if ~isempty(obj.XLineH)    && isvalid(obj.XLineH),    obj.XLineH.Visible    = 'off'; end
            if ~isempty(obj.MarkerH)   && isvalid(obj.MarkerH),   obj.MarkerH.Visible   = 'off'; end
            if ~isempty(obj.HoverTextH) && isvalid(obj.HoverTextH), obj.HoverTextH.Visible = 'off'; end
        end

        function snapAndDisplay(obj, targetX, bypassRadius)
        %SNAPANDDISPLAY  Core snap-to-line + visual update + event fire.
        %   targetX      - X value in data space to snap to
        %   bypassRadius - true: always find nearest (SetPosition)
        %                  false: apply SNAP_RADIUS_PX threshold (UpdateFromMouse)

            ax = obj.AxesH;

            % Find all valid data lines
            allLines = findobj(ax, 'Type', 'line');
            mask     = arrayfun(@(l) ~strcmp(l.Tag, 'cursor'), allLines);
            dataLines = allLines(mask);

            if isempty(dataLines)
                obj.hideAll();
                obj.LastSnappedX = NaN;
                return
            end

            isLogX = strcmp(ax.XScale, 'log');
            xl = xlim(ax);
            xRange = max(xl(2) - xl(1), eps);

            % Edge clamping: pre-compute global data bounds once
            isEdgeClamped = false;
            if ~bypassRadius
                allXData = [];
                for k = 1:numel(dataLines)
                    xd = dataLines(k).XData(:);
                    if ~isempty(xd), allXData = [allXData; xd]; end
                end
                if ~isempty(allXData)
                    isEdgeClamped = targetX >= max(allXData, [], 'omitnan') ...
                                 || targetX <= min(allXData, [], 'omitnan');
                end
            end

            % 1. 正确获取双Y轴物理边界（避免 yyaxis 切换陷阱）
            ylLeft = ax.YAxis(1).Limits;
            if numel(ax.YAxis) > 1 && strcmp(ax.YAxis(2).Visible, 'on')
                ylRight = ax.YAxis(2).Limits;
                hasRightY = true;
            else
                ylRight = ylLeft;
                hasRightY = false;
            end

            mouseY = obj.LastMouseYData;

            bestDist  = inf;
            bestLine  = gobjects(1);
            bestIdx   = 1;
            bestSnapX = NaN;
            bestSnapY = NaN;
            bestIsRightY = false;

            for k = 1:numel(dataLines)
                h  = dataLines(k);
                xd = h.XData(:);
                yd = h.YData(:);
                if isempty(xd) || isempty(yd), continue; end

                if isLogX
                    logXd    = log10(max(xd, realmin));
                    logMouse = log10(max(targetX, realmin));
                    [~, idx] = min(abs(logXd - logMouse));
                else
                    [~, idx] = min(abs(xd - targetX));
                end

                snapX = xd(idx);
                snapY = yd(idx);
                if isnan(snapY), continue; end

                % 2. 匹配当前线的 Y 轴真实范围
                isRightY = strcmp(h.Tag, 'rightY');
                if isRightY
                    lineYLim = ylRight;
                else
                    lineYLim = ylLeft;
                end

                if bypassRadius
                    % Programmatic: X distance only
                    dx = abs(snapX - targetX);
                    if isLogX, dx = abs(log10(max(snapX,realmin)) - log10(max(targetX,realmin))); end
                    if dx < bestDist
                        bestDist  = dx;
                        bestLine  = h;
                        bestIdx   = idx;
                        bestSnapX = snapX;
                        bestSnapY = snapY;
                        bestIsRightY = isRightY;
                    end
                else
                    % 3. X 向归一化距离 (游标存活绝对阈值)
                    dxNorm = abs(snapX - targetX) / xRange;

                    % 4. Y 向跨空间归一化距离
                    % 鼠标 Y 永远基于左 Y 归一化，数据 Y 基于自身坐标系归一化
                    mouseYNorm = (mouseY - ylLeft(1)) / max(ylLeft(2) - ylLeft(1), eps);
                    snapYNorm  = (snapY - lineYLim(1)) / max(lineYLim(2) - lineYLim(1), eps);
                    dyNorm = abs(snapYNorm - mouseYNorm);

                    % 5. X-Only 阈值守卫 (水平距离 < 5% 屏幕宽度即判定吸附)
                    %    Edge clamping: bypass threshold when at data boundary
                    if dxNorm < 0.05 || isEdgeClamped
                        visualDistSq = dxNorm^2 + dyNorm^2;
                        if visualDistSq < bestDist
                            bestDist  = visualDistSq;
                            bestLine  = h;
                            bestIdx   = idx;
                            bestSnapX = snapX;
                            bestSnapY = snapY;
                            bestIsRightY = isRightY;
                        end
                    end
                end
            end

            % 6. 判定脱离逻辑
            if isinf(bestDist) || isnan(bestSnapX)
                obj.hideAll();
                obj.LastSnappedX = NaN;
                obj.LastSnappedY = NaN;
                return
            end

            % Guard: visuals may have been destroyed by cla() between
            % the caller's isvalid check and now (WindowButtonMotionFcn race).
            if ~obj.hasValidVisuals(), return; end

            % Debounce: skip expensive uistack if snap point unchanged
            snapChanged = ~isequal(bestSnapX, obj.LastSnappedX) ...
                       || ~isequal(bestSnapY, obj.LastSnappedY);
            if snapChanged
                % Update hover text and raise Z-layer
            end
            obj.LastSnappedX = bestSnapX;
            obj.LastSnappedY = bestSnapY;
            obj.ActiveLineH = bestLine;

            % Convert rightY snapY to leftY space for display
            % (axes always renders in leftY coordinate system)
            displayY = bestSnapY;
            if bestIsRightY && hasRightY
                snapYNorm = (bestSnapY - ylRight(1)) / max(ylRight(2) - ylRight(1), eps);
                displayY = ylLeft(1) + snapYNorm * max(ylLeft(2) - ylLeft(1), eps);
            end

            % Update lightweight visuals every frame
            obj.XLineH.Value    = bestSnapX;
            obj.XLineH.Visible  = 'on';
            obj.MarkerH.XData   = bestSnapX;
            obj.MarkerH.YData   = displayY;
            obj.MarkerH.Visible = 'on';

            % Expensive operations only when snap point changes
            if snapChanged
                % Hover text: fixed pixel offset (uses correct Y range)
                axPos = hgconvertunits(ancestor(ax,'figure'), ax.Position, ax.Units, 'pixels', ancestor(ax,'figure'));
                pxPerDataX = max(axPos(3) / xRange, eps);
                if bestIsRightY && hasRightY
                    yOffRange = max(ylRight(2) - ylRight(1), eps);
                else
                    yOffRange = max(ylLeft(2) - ylLeft(1), eps);
                end
                pxPerDataY = max(axPos(4) / yOffRange, eps);
                xOff = obj.HOVER_OFFSET_PX / pxPerDataX;
                yOff = obj.HOVER_OFFSET_PX / pxPerDataY;
                obj.HoverTextH.Position = [bestSnapX + xOff, displayY + yOff, 0];
                obj.HoverTextH.String   = obj.LabelFormatterFcn(bestSnapX, bestSnapY);
                obj.HoverTextH.Visible  = 'on';

                % Raise cursor to top Z-layer
                % Skip on dual-Y axes: uistack throws BadChildrenPermutation
                isDualY = numel(ax.YAxis) >= 2 && strcmp(ax.YAxis(2).Visible, 'on');
                if ~isDualY
                    % uistack throws BadChildrenPermutation on some dual-Y
                    % configurations even after the visibility guard above;
                    % safe to ignore since Z-order is cosmetic only.
                    try
                        if isvalid(obj.XLineH),    uistack(obj.XLineH,    'top'); end
                        if isvalid(obj.MarkerH),   uistack(obj.MarkerH,   'top'); end
                        if isvalid(obj.HoverTextH), uistack(obj.HoverTextH, 'top'); end
                    catch  % BadChildrenPermutation — cosmetic, ignore
                    end
                end
            end

            lineTag = '';
            if isprop(bestLine, 'Tag')
                lineTag = bestLine.Tag;
            end

            notify(obj, 'CursorSnapped', ...
                AppEventData(struct( ...
                    'action',   'CursorSnapped', ...
                    'axesIdx',  obj.AxesIdx, ...
                    'x',        bestSnapX, ...
                    'y',        bestSnapY, ...
                    'lineTag',  lineTag, ...
                    'xDataIdx', bestIdx)));
        end

    end
end
