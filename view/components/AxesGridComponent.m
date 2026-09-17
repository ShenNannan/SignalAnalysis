classdef AxesGridComponent < handle
%AXESGRIDCOMPONENT  Data-agnostic dynamic axes grid manager.
%   Owns a uigridlayout and manages 1-N uiaxes with automatic
%   row/column recalculation. Communicates only via events.
%
%   Events:
%     AxesAdded    - struct('action','AxesAdded','axesIdx',N,'handle',hAx)
%     AxesRemoved  - struct('action','AxesRemoved','axesIdx',N,'handle',hAx)

    events
        AxesAdded
        AxesRemoved
    end

    properties (Access = private)
        GridLayout      % uigridlayout handle
        AxesList        % 1xN uiaxes handles (ordered)
        MaxAxes         % hard cap (default 6)
    end

    properties (Dependent, SetAccess = private)
        Count           % current number of axes
        LayoutMode      % "single" | "vert2" | "vert3" | "2x2" | "2x3" | "3x2"
    end

    methods
        function obj = AxesGridComponent(parentFig, varargin)
        %AXESGRIDCOMPONENT  Construct the grid inside a parent figure.
        %   obj = AxesGridComponent(parentFig)
        %   obj = AxesGridComponent(parentFig, 'MaxAxes', 6)

            p = inputParser;
            addRequired(p, 'parentFig');
            addParameter(p, 'MaxAxes', 6, @(x) isnumeric(x) && isscalar(x) && x>=1);
            parse(p, parentFig, varargin{:});

            obj.MaxAxes = p.Results.MaxAxes;
            obj.AxesList = gobjects(1, 0);

            obj.GridLayout = uigridlayout(parentFig, [1 1], ...
                'RowHeight',    {'1x'}, ...
                'ColumnWidth',  {'1x'}, ...
                'Padding',      0, ...
                'RowSpacing',   2, ...
                'ColumnSpacing', 2);
        end

        % ------------------------------------------------------------------
        % Public API
        % ------------------------------------------------------------------

        function hAx = AddAxes(obj)
        %ADDAXES  Append a new uiaxes to the grid.
        %   hAx = AddAxes(obj)
        %   Returns the created axes handle. No-op if at MaxAxes.

            if obj.Count >= obj.MaxAxes
                hAx = gobjects(1);
                return
            end

            obj.AxesList(end+1) = uiaxes(obj.GridLayout);
            hAx = obj.AxesList(end);

            % Initialize with invisible axes properties
            hAx.Toolbar.Visible = 'off';
            hAx.Box = 'on';

            obj.relayoutGrid();
            obj.pumpDrawnow();

            notify(obj, 'AxesAdded', ...
                AppEventData(struct('action','AxesAdded', ...
                                    'axesIdx', obj.Count, ...
                                    'handle',  hAx)));
        end

        function RemoveAxes(obj, idx)
        %REMOVEAXES  Remove axes at index and shift remaining.
        %   RemoveAxes(obj, idx)
        %   idx - 1-based index into AxesList

            arguments
                obj   (1,1) AxesGridComponent
                idx   (1,1) double {mustBePositive, mustBeInteger}
            end

            if idx < 1 || idx > obj.Count
                return
            end

            hAx = obj.AxesList(idx);

            % Delete the UI object first
            if isvalid(hAx)
                delete(hAx);
            end

            obj.AxesList(idx) = [];
            obj.relayoutGrid();
            obj.pumpDrawnow();

            notify(obj, 'AxesRemoved', ...
                AppEventData(struct('action','AxesRemoved', ...
                                    'axesIdx', idx, ...
                                    'handle',  hAx)));
        end

        function Clear(obj)
        %CLEAR  Remove all axes from the grid.

            n = obj.Count;
            for k = n:-1:1
                obj.RemoveAxes(k);
            end
        end

        function hAx = GetAxes(obj, idx)
        %GETAXES  Return the axes handle at a given index.

            arguments
                obj   (1,1) AxesGridComponent
                idx   (1,1) double {mustBePositive, mustBeInteger}
            end

            if idx >= 1 && idx <= obj.Count
                hAx = obj.AxesList(idx);
            else
                hAx = gobjects(1);
            end
        end

        function list = GetAllAxes(obj)
        %GETALLAXES  Return the full AxesList row vector.
            list = obj.AxesList;
        end
    end

    % ------------------------------------------------------------------
    % Dependent getters
    % ------------------------------------------------------------------
    methods
        function n = get.Count(obj)
            n = numel(obj.AxesList);
        end

        function mode = get.LayoutMode(obj)
            switch obj.Count
                case 1,     mode = "single";
                case 2,     mode = "vert2";
                case 3,     mode = "vert3";
                case 4,     mode = "2x2";
                case 5,     mode = "2x3";
                case 6,     mode = "3x2";
                otherwise,  mode = "empty";
            end
        end
    end

    % ------------------------------------------------------------------
    % Private helpers
    % ------------------------------------------------------------------
    methods (Access = private)

        function relayoutGrid(obj)
        %RELAYOUTGRID  Recalculate grid rows/columns for current Count.
        %   Layout map (all axes go row-major into the grid):
        %     Count 1  -> 1x1
        %     Count 2  -> 2x1 (vertical stack)
        %     Count 3  -> 3x1
        %     Count 4  -> 2x2
        %     Count 5  -> 3x2  (last cell empty)
        %     Count 6  -> 3x2

            n = obj.Count;

            if n == 0
                obj.GridLayout.RowHeight    = {'1x'};
                obj.GridLayout.ColumnWidth  = {'1x'};
                return
            end

            switch n
                case 1
                    nrows = 1; ncols = 1;
                case 2
                    nrows = 2; ncols = 1;
                case 3
                    nrows = 3; ncols = 1;
                case {4}
                    nrows = 2; ncols = 2;
                case {5, 6}
                    nrows = 3; ncols = 2;
                otherwise
                    nrows = ceil(n/2); ncols = 2;
            end

            obj.GridLayout.RowHeight    = repmat({'1x'}, 1, nrows);
            obj.GridLayout.ColumnWidth  = repmat({'1x'}, 1, ncols);

            % Re-parent each axes into the correct cell (row-major order)
            for k = 1:n
                row = ceil(k / ncols);
                col = k - (row-1)*ncols;
                obj.AxesList(k).Layout.Row    = row;
                obj.AxesList(k).Layout.Column = col;
            end
        end

        function pumpDrawnow(obj)  %#ok<MANU>
        %PUMPDRAWNOW  Force 40 drawnow limitrate to flush layout.
            for p = 1:40
                drawnow limitrate
            end
        end
    end
end
