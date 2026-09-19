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
        ItemRenameRequested  % struct('oldName','...','newName','...','isParent',T/F,'datasetIdx',..,'colIdx',..)
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
        LastClickedRow  double = 0

        % Menu item handles (for Enable toggling)
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

        function delete(obj)
        %DELETE  Destroy owned UI objects on component teardown.
            if ~isempty(obj.ContextMenuH) && isvalid(obj.ContextMenuH)
                delete(obj.ContextMenuH);
            end
            if ~isempty(obj.TableH) && isvalid(obj.TableH)
                delete(obj.TableH);
            end
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
                'ColumnEditable',       [true true], ...
                'ColumnWidth',          {38, '1x'}, ...
                'FontName',             'Consolas', ...
                'SelectionHighlight',   'on');

            obj.TableH.Data = table(false(0,1), cell(0,1), ...
                'VariableNames', {'选择', '数据集'});

            obj.TableH.CellEditCallback     = @(s,e) obj.onCellEdit(e);
            obj.TableH.CellSelectionCallback = @(s,e) obj.onCellSelect(e);
        end

        function buildContextMenu(obj)
            fig = ancestor(obj.TableH, 'figure');
            cm  = uicontextmenu(fig);

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
        %REBUILDDATA  Rebuild visible rows with Unicode tree topology.
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
                    checked{end+1} = logical(r.checked);  %#ok<AGROW>
                    if isempty(r.datasetName)
                        names{end+1} = r.label;           %#ok<AGROW>
                    else
                        names{end+1} = r.datasetName;     %#ok<AGROW>
                    end
                    visMap(end+1) = i;                     %#ok<AGROW>
                    dsKey = num2str(r.datasetIdx);
                    if obj.ExpandedSets.isKey(dsKey) && obj.ExpandedSets(dsKey)
                        % expanded → continue to show children
                    else
                        continue
                    end
                else
                    parentDs = rows(i).datasetIdx;
                    dsKey = num2str(parentDs);
                    if obj.ExpandedSets.isKey(dsKey) && obj.ExpandedSets(dsKey)
                        checked{end+1} = logical(r.checked); %#ok<AGROW>
                        shortLabel = r.label;
                        if startsWith(shortLabel, '/')
                            shortLabel = strtrim(extractAfter(shortLabel, 1));
                        end
                        % Determine if last child in this dataset
                        isLast = (i == numel(rows)) || rows(i+1).isParent ...
                              || rows(i+1).datasetIdx ~= parentDs;
                        if isLast
                            names{end+1} = ['    └─ ' shortLabel]; %#ok<AGROW>
                        else
                            names{end+1} = ['    ├─ ' shortLabel]; %#ok<AGROW>
                        end
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
        %ONCELLEDIT  Checkbox toggle or inline rename with regex self-healing.
            if obj.Rebuilding || isempty(obj.VisibleRowMap)
                return
            end
            visRow = e.Indices(1);
            if visRow < 1 || visRow > numel(obj.VisibleRowMap)
                return
            end
            internalIdx = obj.VisibleRowMap(visRow);
            r = obj.ChannelRows(internalIdx);

            % --- Column 2: inline rename with self-healing ---
            if e.Indices(2) == 2
                cleanOld = obj.getCleanName(e.PreviousData);
                cleanNew = obj.getCleanName(e.NewData);

                if isempty(cleanNew) || strcmp(cleanOld, cleanNew)
                    % Rollback: restore decorated display
                    obj.Rebuilding = true;
                    obj.setTableCol2(visRow, e.PreviousData);
                    obj.Rebuilding = false;
                    return
                end

                % Emit pure rename payload → Presenter will re-render with
                % fresh tree decoration, achieving visual self-healing.
                payload = struct('action',    'rename', ...
                                 'oldName',   cleanOld, ...
                                 'newName',   cleanNew, ...
                                 'isParent',  r.isParent, ...
                                 'datasetIdx', r.datasetIdx, ...
                                 'colIdx',     r.colIdx);
                notify(obj, 'ItemRenameRequested', AppEventData(payload));
                return
            end

            % --- Column 1: checkbox toggle ---
            if e.Indices(2) ~= 1, return; end
            val = logical(obj.TableH.Data{visRow, 1});
            payload = struct('action', 'checkChanged', ...
                             'datasetIdx', r.datasetIdx, ...
                             'colIdx',     r.colIdx, ...
                             'checked',    val);
            notify(obj, 'ActionRequested', AppEventData(payload));
        end

        function cleanName = getCleanName(~, rawString)
        %GETCLEANNAME  Regex decoder: strip tree prefixes and axis tags.
            if isempty(rawString) || (~ischar(rawString) && ~isstring(rawString))
                cleanName = ''; return;
            end
            cleanName = regexprep(char(rawString), '^\s*[├└]─\s*', '');
            cleanName = regexprep(cleanName, '\s*\[[A-Za-z0-9]+\]\s*$', '');
            cleanName = strtrim(cleanName);
        end

        function onCellSelect(obj, e)
        %ONCELLSELECT  Row click → expand/collapse datasets.
            if obj.Highlighting || obj.Rebuilding, return; end

            if ~isempty(e.Indices)
                obj.TableH.Selection = [e.Indices(1), 1; e.Indices(1), 2];
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
