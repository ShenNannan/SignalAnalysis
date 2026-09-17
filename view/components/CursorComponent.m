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
        LabelFormatterFcn   function_handle = @(y) sprintf('%.6g', y)
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
        LastSnappedX       double = NaN   % motion debounce
    end

    properties (Constant, Access = private)
        CURSOR_COLOR   = [0.85 0.32 0.09]
        SNAP_RADIUS_PX = 30   % max snap distance in pixels
        X_OFFSET_FRAC  = 0.015
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
                'Visible',          'off');

            % Hover text
            obj.HoverTextH = text(ax, 0, 0, '', ...
                'BackgroundColor',      [1 1 1 0.85], ...
                'EdgeColor',            [0.5 0.5 0.5], ...
                'Margin',               4, ...
                'FontSize',             9, ...
                'HitTest',              'off', ...
                'PickableParts',        'none', ...
                'VerticalAlignment',    'bottom', ...
                'Visible',              'off');
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

        function UpdateFromMouse(obj, mouseXPixel, mouseYPixel)
        %UPDATEFROMMOUSE  Drive cursor from raw pixel coordinates.
        %   Call from a WindowButtonMotionFcn (or AxesButtondownFcn).
        %   mouseXPixel / mouseYPixel are in axes pixel space.

            if obj.IsUpdating, return; end
            if ~isvalid(obj.AxesH), return; end
            if ~obj.hasValidVisuals(), return; end

            obj.IsUpdating = true;
            cleanupObj = onCleanup(@() obj.unlock());  %#ok<NASGU>

            % Convert pixel → data coordinates
            ax = obj.AxesH;
            cp = obj.pixelToData(ax, mouseXPixel, mouseYPixel);
            mouseXData = cp(1);

            % Debounce: same X → skip
            if ~isnan(obj.LastSnappedX) && mouseXData == obj.LastSnappedX
                return
            end

            obj.snapAndDisplay(mouseXData, false);
        end

        function Hide(obj)
        %HIDE  Manually hide all cursor visuals.
            obj.hideAll();
            obj.LastSnappedX = NaN;
        end

        function RebuildOnAxes(obj)
        %REBUILDONAXES  Re-create cursor objects after cla().
        %   Call after the owning axes has been cleared.
        %   Uses per-object try-catch to survive R2025b transient failures.
            ax = obj.AxesH;
            if ~isvalid(ax), return; end

            % Flush graphics pipeline after cla() to stabilize axes state
            try
                drawnow limitrate;
            catch
            end

            try
                obj.XLineH = xline(ax, 0, ...
                    'Color', obj.CURSOR_COLOR, 'LineWidth', 1.2, ...
                    'LineStyle', '-', 'HitTest', 'off', ...
                    'PickableParts', 'none', 'Visible', 'off', ...
                    'HandleVisibility', 'off');
            catch
            end

            try
                obj.MarkerH = line(ax, NaN, NaN, ...
                    'Marker', 'o', 'MarkerSize', 6, ...
                    'MarkerFaceColor', obj.CURSOR_COLOR, ...
                    'MarkerEdgeColor', 'w', 'LineStyle', 'none', ...
                    'HitTest', 'off', 'PickableParts', 'none', ...
                    'Tag', 'cursor', 'XLimInclude', 'off', ...
                    'YLimInclude', 'off', 'Visible', 'off');
            catch
            end

            try
                obj.HoverTextH = text(ax, 0, 0, '', ...
                    'BackgroundColor', [1 1 1 0.85], ...
                    'EdgeColor', [0.5 0.5 0.5], 'Margin', 4, ...
                    'FontSize', 9, 'HitTest', 'off', ...
                    'PickableParts', 'none', ...
                    'VerticalAlignment', 'bottom', 'Visible', 'off');
            catch
            end
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

            bestDist  = inf;
            bestLine  = gobjects(1);
            bestIdx   = 1;
            bestSnapX = NaN;
            bestSnapY = NaN;

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

                if ~bypassRadius
                    isRightY = strcmp(h.Tag, 'rightY');
                    if isRightY
                        ptPixelX = obj.dataToPixel(ax, [snapX, 0]);
                        pxDist   = abs(ptPixelX(1));  % relative to axes origin
                    else
                        ptPixel = obj.dataToPixel(ax, [snapX, snapY]);
                        pxDist  = hypot(ptPixel(1), ptPixel(2));
                    end
                    if pxDist < bestDist
                        bestDist  = pxDist;
                        bestLine  = h;
                        bestIdx   = idx;
                        bestSnapX = snapX;
                        bestSnapY = snapY;
                    end
                else
                    % Bypass mode: pick by data-space X closeness only
                    dx = abs(snapX - targetX);
                    if isLogX, dx = abs(log10(max(snapX,realmin)) - log10(max(targetX,realmin))); end
                    if dx < bestDist
                        bestDist  = dx;
                        bestLine  = h;
                        bestIdx   = idx;
                        bestSnapX = snapX;
                        bestSnapY = snapY;
                    end
                end
            end

            if (~bypassRadius && bestDist > obj.SNAP_RADIUS_PX) || isnan(bestSnapX)
                obj.hideAll();
                obj.LastSnappedX = NaN;
                return
            end

            obj.LastSnappedX = bestSnapX;

            % Guard: visuals may have been destroyed by cla() between
            % the caller's isvalid check and now (WindowButtonMotionFcn race).
            if ~obj.hasValidVisuals(), return; end

            % Update visuals
            obj.XLineH.Value    = bestSnapX;
            obj.XLineH.Visible  = 'on';
            obj.MarkerH.XData   = bestSnapX;
            obj.MarkerH.YData   = bestSnapY;
            obj.MarkerH.Visible = 'on';

            xl = xlim(ax); yl = ylim(ax);
            xOffset = obj.X_OFFSET_FRAC * (xl(2) - xl(1));
            yOffset = 0.015 * (yl(2) - yl(1));
            obj.HoverTextH.Position = [bestSnapX + xOffset, bestSnapY + yOffset, 0];
            obj.HoverTextH.String   = obj.LabelFormatterFcn(bestSnapY);
            obj.HoverTextH.Visible  = 'on';

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

        function dataPt = pixelToData(obj, ax, px, py)
        %PIXELTODATA  Convert axes-pixel coordinates to data coordinates.
        %   Uses the axes Transform inverse (R2020b+), with linear fallback.

            try
                T = ax.Transform;
                dataPt = T.Inverse * [px; py; 0; 1];
                dataPt = dataPt(1:2)';
            catch
                dataPt = obj.interpPixelData(ax, px, py, 'pixel2data');
            end
        end

        function pixPt = dataToPixel(obj, ax, dataXY)
        %DATATOPIXEL  Convert data coordinates to axes-pixel coordinates.
        %   dataXY = [dataX, dataY] in left-Y coordinate system.
        %   Returns [pixelX, pixelY].

            try
                T = ax.Transform;
                pixPt = T * [dataXY(1); dataXY(2); 0; 1];
                pixPt = pixPt(1:2)';
            catch
                pixPt = obj.interpPixelData(ax, dataXY(1), dataXY(2), 'data2pixel');
            end
        end

        function out = interpPixelData(~, ax, v1, v2, direction)
        %INTERPIXELDATA  Fallback coordinate conversion via linear interp.
            oldUnits = ax.Units;
            ax.Units = 'pixels';
            axPos = ax.Position;
            ax.Units = oldUnits;

            xl = xlim(ax); yl = ylim(ax);

            isLogX = strcmp(ax.XScale, 'log');
            isLogY = strcmp(ax.YScale, 'log');

            if isLogX, xl = log10(max(xl, realmin)); end
            if isLogY, yl = log10(max(yl, realmin)); end

            switch direction
                case 'pixel2data'
                    nx = (v1 - axPos(1)) / axPos(3);
                    ny = (v2 - axPos(2)) / axPos(4);
                    ox = xl(1) + nx * (xl(2) - xl(1));
                    oy = yl(1) + ny * (yl(2) - yl(1));
                    if isLogX, ox = 10^ox; end
                    if isLogY, oy = 10^oy; end
                    out = [ox, oy];
                case 'data2pixel'
                    dx = v1; dy = v2;
                    if isLogX, dx = log10(max(dx, realmin)); end
                    if isLogY, dy = log10(max(dy, realmin)); end
                    nx = (dx - xl(1)) / max(xl(2) - xl(1), eps);
                    ny = (dy - yl(1)) / max(yl(2) - yl(1), eps);
                    out = [axPos(1) + nx*axPos(3), axPos(2) + ny*axPos(4)];
            end
        end
    end
end
