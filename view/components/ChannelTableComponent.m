classdef ChannelTableComponent < handle
%CHANNELTABLECOMPONENT  Channel table with context-menu state machine.
%   Owns a uitable + uicontextmenu. Enforces mutual-exclusion rules
%   for axis-assignment menu items. All actions bubble out via events.
%
%   Input state (set by Presenter through UpdateXChannel / UpdateRightY):
%     CurXChannel    - [dsIdx, colIdx] or []   (current X-axis channel)
%     CurRightYList  - cell of [dsIdx, colIdx] (current right-Y channels)
%
%   Events (all carry AppEventData):
%     ActionRequested  - generic action bus: struct('action','...','datasetIdx',..,'colIdx',..)

    events
        ActionRequested
    end

    properties (SetAccess = private)
        TableH              % uitable handle
        ContextMenuH        % uicontextmenu handle
    end

    properties (Access = private)
        ParentFig           % owning figure (for context menu)
        ChannelRows         % row metadata: struct array {isParent,datasetIdx,colIdx,label,datasetName}
        VisibleRowMap       % visible-row → ChannelRows index
        ExpandedSets        % containers.Map: datasetIdx → logical
        CurXChannel  double = []   % [dsIdx, colIdx]
        CurRightYList       % cell of [dsIdx, colIdx]

        % Internal state flags
        Highlighting logical = false
        Rebuilding   logical = false
        Renaming     logical = false
        RenameOriginal  string = ""
        LastClickedRow  double = 0

        % Menu item handles (for Enable toggling)
        MenuRename
        MenuSampleRate
        MenuExportExcel
        MenuSlice
        MenuSliceReset
        MenuSetXAxis
        MenuClearXAxis
        MenuSetRightY
        MenuClearRightY
    end

    methods
        function obj = ChannelTableComponent(parentFig)
        %CHANNELTABLECOMPONENT  Create the table and context menu inside parentFig.

            arguments
                parentFig (1,1)
            end

            obj.ParentFig    = parentFig;
            obj.ExpandedSets = containers.Map('KeyType',   'char', ...
                                              'ValueType', 'logical');
            obj.CurRightYList = {};

            obj.buildTable();
            obj.buildContextMenu();
        end

        % ------------------------------------------------------------------
        % Public state setters (called by Presenter / View)
        % ------------------------------------------------------------------

        function SetRows(obj, rows)
        %SETROWS  Full refresh of table data.
        %   rows: struct array with fields:
        %     isParent, datasetIdx, colIdx, label, datasetName, checked

            obj.ChannelRows = rows;
            obj.rebuildData();
        end

        function UpdateXChannel(obj, dsIdx, colIdx)
        %UPDATEXCHANNEL  Tell the component which channel is current X.
        %   Pass [] to clear.
            if nargin < 3 || isempty(dsIdx)
                obj.CurXChannel = [];
            else
                obj.CurXChannel = [dsIdx, colIdx];
            end
        end

        function UpdateRightY(obj, rightYList)
        %UPDATERIGHTY  Tell the component which channels are right-Y.
        %   rightYList: cell of [dsIdx, colIdx], or {} to clear.
            if nargin < 2, rightYList = {}; end
            obj.CurRightYList = rightYList;
        end

        function h = GetTableHandle(obj)
        %GETTABLEHANDLE  Return the raw uitable handle (for layout parenting).
            h = obj.TableH;
        end
    end

    % ------------------------------------------------------------------
    % Construction helpers
    % ------------------------------------------------------------------
    methods (Access = private)

        function buildTable(obj)
            obj.TableH = uitable(obj.ParentFig, ...
                'ColumnName',           {'选择', '数据集'}, ...
                'ColumnEditable',       [true false], ...
                'ColumnWidth',          {38, '1x'}, ...
                'SelectionHighlight',   'on');

            obj.TableH.Data = table(false(0,1), cell(0,1), ...
                'VariableNames', {'选择', '数据集'});

            obj.TableH.CellEditCallback     = @(s,e) obj.onCellEdit(e);
            obj.TableH.CellSelectionCallback = @(s,e) obj.onCellSelect(e);
        end

        function buildContextMenu(obj)
            fig = ancestor(obj.TableH, 'figure');
            cm  = uicontextmenu(fig);

            obj.MenuRename      = uimenu(cm, 'Text', '重命名', ...
                'MenuSelectedFcn', @(s,e) obj.onContextRename());
            obj.MenuSampleRate  = uimenu(cm, 'Text', '设置采样频率...', ...
                'MenuSelectedFcn', @(s,e) obj.fire('setSampleRate'));
            obj.MenuExportExcel = uimenu(cm, 'Text', '导出 Excel', ...
                'MenuSelectedFcn', @(s,e) obj.fire('exportExcel'));
            obj.MenuSlice       = uimenu(cm, 'Text', '设置切片范围...', 'Separator','on', ...
                'MenuSelectedFcn', @(s,e) obj.fire('slice'));
            obj.MenuSliceReset  = uimenu(cm, 'Text', '切片重置', ...
                'MenuSelectedFcn', @(s,e) obj.fire('sliceReset'));
            obj.MenuSetXAxis    = uimenu(cm, 'Text', '设为横轴', 'Separator','on', ...
                'MenuSelectedFcn', @(s,e) obj.fire('setXAxis'));
            obj.MenuClearXAxis  = uimenu(cm, 'Text', '恢复默认横轴', 'Enable','off', ...
                'MenuSelectedFcn', @(s,e) obj.fire('clearXAxis'));
            obj.MenuSetRightY   = uimenu(cm, 'Text', '设为右 Y 轴', ...
                'MenuSelectedFcn', @(s,e) obj.fire('setRightY'));
            obj.MenuClearRightY = uimenu(cm, 'Text', '恢复默认 Y 轴', 'Enable','off', ...
                'MenuSelectedFcn', @(s,e) obj.fire('clearRightY'));

            obj.TableH.ContextMenu = cm;
            cm.ContextMenuOpeningFcn = @(s,e) obj.onContextMenuOpening();
            obj.ContextMenuH = cm;
        end
    end

    % ------------------------------------------------------------------
    % Table data rebuild (collapse / expand logic)
    % ------------------------------------------------------------------
    methods (Access = private)

        function rebuildData(obj)
        %REBUILDDATA  Rebuild visible rows respecting ExpandedSets.
            rows = obj.ChannelRows;
            if isempty(rows)
                obj.Rebuilding = true;
                obj.TableH.Data = table(logical([]), cell(0,1), ...
                    'VariableNames', {'选择', '数据集'});
                obj.Rebuilding = false;
                obj.VisibleRowMap = [];
                return
            end

            checked = {};
            names   = {};
            visMap  = [];

            for i = 1:numel(rows)
                r = rows(i);
                if r.isParent
                    % Dataset row: always visible
                    checked{end+1} = logical(r.checked);  %#ok<AGROW>
                    if isempty(r.datasetName)
                        names{end+1} = r.label;           %#ok<AGROW>
                    else
                        names{end+1} = r.datasetName;     %#ok<AGROW>
                    end
                    visMap(end+1) = i;                     %#ok<AGROW>
                    % If collapsed, skip children
                    dsKey = num2str(r.datasetIdx);
                    if obj.ExpandedSets.isKey(dsKey) && obj.ExpandedSets(dsKey)
                        % expanded → continue to show children
                    else
                        % Skip children until next parent
                        continue
                    end
                else
                    % Channel row: show only if parent is expanded
                    parentDs = rows(i).datasetIdx;
                    dsKey = num2str(parentDs);
                    if obj.ExpandedSets.isKey(dsKey) && obj.ExpandedSets(dsKey)
                        checked{end+1} = logical(r.checked); %#ok<AGROW>
                        shortLabel = r.label;
                        if startsWith(shortLabel, '/')
                            shortLabel = strtrim(extractAfter(shortLabel, 1));
                        end
                        names{end+1} = shortLabel;          %#ok<AGROW>
                        visMap(end+1) = i;                    %#ok<AGROW>
                    end
                end
            end

            obj.VisibleRowMap = visMap;
            obj.Rebuilding = true;
            if isempty(checked)
                obj.TableH.Data = table(logical([]), cell(0,1), ...
                    'VariableNames', {'选择', '数据集'});
            else
                obj.TableH.Data = table([checked{:}]', names(:), ...
                    'VariableNames', {'选择', '数据集'});
            end
            obj.Rebuilding = false;
        end
    end

    % ------------------------------------------------------------------
    % Table callbacks (internal)
    % ------------------------------------------------------------------
    methods (Access = private)

        function onCellEdit(obj, e)
        %ONCELLEDIT  Checkbox toggle or rename commit.
            if obj.Rebuilding || isempty(obj.VisibleRowMap)
                return
            end
            visRow = e.Indices(1);
            if visRow < 1 || visRow > numel(obj.VisibleRowMap)
                return
            end
            internalIdx = obj.VisibleRowMap(visRow);
            r = obj.ChannelRows(internalIdx);

            % --- Rename commit (column 2) ---
            if e.Indices(2) == 2 && obj.Renaming
                if visRow ~= obj.LastClickedRow
                    obj.Renaming = false;
                    obj.TableH.ColumnEditable(2) = false;
                    return
                end
                obj.Renaming = false;
                obj.TableH.ColumnEditable(2) = false;
                newName = strtrim(obj.TableH.Data{visRow, 2});
                if isempty(newName) || newName == obj.RenameOriginal
                    obj.Rebuilding = true;
                    obj.setTableCol2(visRow, r.label);
                    obj.Rebuilding = false;
                    return
                end
                if r.isParent
                    obj.notifyAction('renameDataset', r.datasetIdx, 0, newName);
                else
                    obj.notifyAction('renameChannel', r.datasetIdx, r.colIdx, newName);
                end
                return
            end

            % --- Checkbox toggle (column 1) ---
            if e.Indices(2) ~= 1, return; end
            val = logical(obj.TableH.Data{visRow, 1});
            payload = struct('action', 'checkChanged', ...
                             'datasetIdx', r.datasetIdx, ...
                             'colIdx',     r.colIdx, ...
                             'checked',    val);
            notify(obj, 'ActionRequested', AppEventData(payload));
        end

        function onCellSelect(obj, e)
        %ONCELLSELECT  Row click → expand/collapse datasets.
            if obj.Highlighting || obj.Rebuilding, return; end

            if ~isempty(e.Indices)
                obj.TableH.Selection = [e.Indices(1), 1; e.Indices(1), 2];
            end

            % Renaming and clicked elsewhere → abort rename
            if obj.Renaming
                obj.Renaming = false;
                obj.TableH.ColumnEditable(2) = false;
                return
            end

            if isempty(e.Indices), return; end
            visRow = e.Indices(1);
            obj.LastClickedRow = visRow;

            if visRow < 1 || visRow > numel(obj.VisibleRowMap), return; end
            internalIdx = obj.VisibleRowMap(visRow);
            r = obj.ChannelRows(internalIdx);
            if ~r.isParent, return; end

            % Toggle expand/collapse
            dsKey = num2str(r.datasetIdx);
            if obj.ExpandedSets.isKey(dsKey)
                obj.ExpandedSets(dsKey) = ~obj.ExpandedSets(dsKey);
            else
                obj.ExpandedSets(dsKey) = true;
            end
            obj.rebuildData();

            % Re-select the row to keep highlight
            obj.Highlighting = true;
            obj.TableH.Selection = [visRow, 1; visRow, 2];
            obj.Highlighting = false;
        end
    end

    % ------------------------------------------------------------------
    % Context menu state machine
    % ------------------------------------------------------------------
    methods (Access = private)

        function onContextMenuOpening(obj)
        %ONCONTEXTMENUOPENING  Select row + update menu Enable states.

            % Auto-select the last left-clicked row
            nRows = size(obj.TableH.Data, 1);
            if obj.LastClickedRow >= 1 && obj.LastClickedRow <= nRows
                obj.Highlighting = true;
                obj.TableH.Selection = [obj.LastClickedRow, 1; obj.LastClickedRow, 2];
                obj.Highlighting = false;
            end

            % Resolve row type
            [r, isChannel] = obj.resolveRow(obj.LastClickedRow);

            isXChannel = false;
            isRightY   = false;
            dsIdx = 0; chIdx = 0;

            if isChannel
                dsIdx = r.datasetIdx;
                chIdx = r.colIdx;
                isXChannel = ~isempty(obj.CurXChannel) ...
                    && obj.CurXChannel(1) == dsIdx ...
                    && obj.CurXChannel(2) == chIdx;
                isRightY = obj.isInRightYList(dsIdx, chIdx);
            end

            % Mutual-exclusion rules
            obj.setEnable(obj.MenuSetXAxis,    isChannel && ~isXChannel);
            obj.setEnable(obj.MenuClearXAxis,  isChannel &&  isXChannel);
            obj.setEnable(obj.MenuSetRightY,   isChannel && ~isRightY && ~isXChannel);
            obj.setEnable(obj.MenuClearRightY, isChannel &&  isRightY);

            % Row-type-only items
            obj.setEnable(obj.MenuSampleRate, ~isChannel);   % dataset only
            obj.setEnable(obj.MenuSlice,       isChannel);
            obj.setEnable(obj.MenuSliceReset,  isChannel);
        end

        function onContextRename(obj)
        %ONCONTEXTRENAME  Enable inline edit on column 2.
            if isempty(obj.VisibleRowMap), return; end
            visRow = obj.LastClickedRow;
            if visRow < 1 || visRow > numel(obj.VisibleRowMap), return; end

            internalIdx = obj.VisibleRowMap(visRow);
            r = obj.ChannelRows(internalIdx);
            obj.RenameOriginal = string(r.label);
            obj.Renaming = true;
            obj.TableH.ColumnEditable(2) = true;
            obj.TableH.Selection = [visRow, 2];
            focus(obj.TableH);
        end
    end

    % ------------------------------------------------------------------
    % Fire helpers
    % ------------------------------------------------------------------
    methods (Access = private)

        function fire(obj, action)
        %FIRE  Resolve right-click row and emit ActionRequested.
            visRow = obj.getVisibleRow();
            if isempty(visRow), return; end
            internalIdx = obj.VisibleRowMap(visRow);
            r = obj.ChannelRows(internalIdx);

            % Dataset-only actions
            if r.isParent
                if strcmp(action, 'setSampleRate') || strcmp(action, 'exportExcel')
                    obj.notifyAction(action, r.datasetIdx, 0, []);
                end
                return
            end

            % Channel actions
            switch action
                case {'slice', 'sliceReset', 'setSampleRate'}
                    obj.notifyAction(action, r.datasetIdx, r.colIdx, []);
                case 'setXAxis'
                    obj.notifyAction(action, r.datasetIdx, r.colIdx, []);
                case 'clearXAxis'
                    obj.notifyAction(action, 0, 0, []);  % axesIdx resolved by Presenter
                case 'setRightY'
                    obj.notifyAction(action, r.datasetIdx, r.colIdx, []);
                case 'clearRightY'
                    obj.notifyAction(action, 0, 0, []);
                case 'exportExcel'
                    obj.notifyAction(action, r.datasetIdx, 0, []);
            end
        end

        function notifyAction(obj, action, dsIdx, colIdx, extra)
        %NOTIFYACTION  Unified event emission.
            payload = struct('action', action, ...
                             'datasetIdx', dsIdx, ...
                             'colIdx',     colIdx);
            if ~isempty(extra)
                payload.value = extra;
            end
            notify(obj, 'ActionRequested', AppEventData(payload));
        end

        function row = getVisibleRow(obj)
        %GETVISIBLEROW  Return last-clicked visible row index, or [].
            row = [];
            if isempty(obj.VisibleRowMap), return; end
            r = obj.LastClickedRow;
            if r >= 1 && r <= numel(obj.VisibleRowMap)
                row = r;
            end
        end

        function [r, isChannel] = resolveRow(obj, visRow)
        %RESOLVEROW  Map visible row to ChannelRows entry.
            r = struct();
            isChannel = false;
            if isempty(obj.VisibleRowMap), return; end
            if visRow < 1 || visRow > numel(obj.VisibleRowMap), return; end
            internalIdx = obj.VisibleRowMap(visRow);
            r = obj.ChannelRows(internalIdx);
            isChannel = ~r.isParent;
        end

        function tf = isInRightYList(obj, dsIdx, chIdx)
        %ISINRIGHTYLIST  Check if (dsIdx,chIdx) is in CurRightYList.
            tf = false;
            for k = 1:numel(obj.CurRightYList)
                pair = obj.CurRightYList{k};
                if pair(1) == dsIdx && pair(2) == chIdx
                    tf = true;
                    return
                end
            end
        end

        function setEnable(~, menuH, flag)
        %SETENABLE  Toggle a uimenu Enable property.
            if flag
                menuH.Enable = 'on';
            else
                menuH.Enable = 'off';
            end
        end

        function setTableCol2(obj, row, value)
        %SETTABLECOL2  R2025b-safe cell-column assignment for column 2.
        %   Avoids T{r,v}=char / T.col{r}=char which raise WrongNumberRHSCols.
            data = obj.TableH.Data;
            colName = data.Properties.VariableNames{2};
            col = data.(colName);    % explicit copy (cell array)
            col{row} = value;        % standard cell assignment
            data.(colName) = col;    % write column back
            obj.TableH.Data = data;
        end
    end
end
