classdef TestChannelTableComponent < matlab.unittest.TestCase
%TESTCHANNELTABLECOMPONENT  5-dimension MECE test matrix for ChannelTableComponent.
%
%   D1: Data boundaries (empty rows, expand/collapse, empty indices)
%   D2: Checkbox toggle + Menu state machine (parent/channel/X-axis/rightY)
%   D3: Rename behavior (dataset, channel, empty, same, abort)
%   D4: All 8 channel-menu actions + Stress (SetRows 100x, checkbox 100x)
%   D5: Exception injection (empty VisibleRowMap guard, out-of-range visRow)

    properties
        Fig
        Comp
    end

    methods (TestMethodSetup)
        function createFixture(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            addpath(fullfile(root, 'view'));
            addpath(fullfile(root, 'view', 'components'));
            addpath(fullfile(root, 'model'));
            addpath(fullfile(root, 'presenter'));
            addpath(fullfile(root, 'service'));
            addpath(root);
            testCase.Fig = uifigure('Visible', 'off');
            testCase.Comp = ChannelTableComponent(testCase.Fig);
            testCase.Comp.SetRows(buildMockRows());
        end
    end

    methods (TestMethodTeardown)
        function destroyFixture(testCase)
            if isvalid(testCase.Fig)
                delete(testCase.Fig);
            end
        end
    end

    methods (Access = private)
        function expandDS(testCase)
            th = testCase.Comp.GetTableHandle();
            th.CellSelectionCallback(th, struct('Indices', [1, 1]));
            pause(0.05);
        end

        function selectRow(testCase, visRow)
            th = testCase.Comp.GetTableHandle();
            th.CellSelectionCallback(th, struct('Indices', [visRow, 1]));
            pause(0.02);
        end

        function openContextMenu(testCase)
            th = testCase.Comp.GetTableHandle();
            cm = th.ContextMenu;
            cm.ContextMenuOpeningFcn(cm, []);
            pause(0.05);
        end

        function cm = getContextMenu(testCase)
            th = testCase.Comp.GetTableHandle();
            cm = th.ContextMenu;
        end

        function assertMenuState(testCase, cm, menuText, expectedEnable)
            m = findMenuByText(cm, menuText);
            testCase.verifyEqual(string(m.Enable), string(expectedEnable), ...
                sprintf('Menu "%s": expected %s, got %s', ...
                menuText, expectedEnable, string(m.Enable)));
        end

        function startRename(testCase, visRow)
        %STARTRENAME  No-op: column 2 is now always editable.
            testCase.selectRow(visRow);
        end

        function commitRename(testCase, visRow, newName)
            th = testCase.Comp.GetTableHandle();
            oldRaw = th.Data{visRow, 2};
            if iscell(oldRaw), oldRaw = oldRaw{1}; end
            % Fire CellEditCallback with PreviousData + NewData
            th.CellEditCallback(th, struct( ...
                'Indices', [visRow, 2], ...
                'PreviousData', oldRaw, ...
                'NewData', newName));
            pause(0.05);
        end

        function runMenuAction(testCase, selectVisRow, menuText, ...
                               expectAction, expectDs, expectCol)
            testCase.selectRow(selectVisRow);
            testCase.openContextMenu();
            cm = testCase.getContextMenu();

            cap = EventCapture();
            lh = addlistener(testCase.Comp, 'ActionRequested', ...
                @(~,e) cap.store(e));
            m = findMenuByText(cm, menuText);
            m.MenuSelectedFcn(m, []);
            pause(0.05);

            testCase.verifyNotEmpty(cap.Events, sprintf('%s should fire', menuText));
            p = cap.Events{1};
            testCase.verifyEqual(p.action, expectAction);
            testCase.verifyEqual(p.datasetIdx, expectDs);
            testCase.verifyEqual(p.colIdx, expectCol);
            delete(lh);
        end
    end

    methods (Test)
        %% ===== D1: Data Boundaries =====

        function test_EmptyRows_NoCrash(testCase)
            testCase.Comp.SetRows([]);
            th = testCase.Comp.GetTableHandle();
            testCase.verifyEqual(size(th.Data, 1), 0);
        end

        function test_Expand_ShowsChildren(testCase)
            th = testCase.Comp.GetTableHandle();
            testCase.verifyEqual(size(th.Data, 1), 2, 'Should start collapsed');

            testCase.expandDS();
            th = testCase.Comp.GetTableHandle();
            testCase.verifyEqual(size(th.Data, 1), 4, ...
                'Should show 4 rows after expand (DS1+ch1+ch2, DS2)');
        end

        function test_Collapse_HidesChildren(testCase)
            testCase.expandDS();
            th = testCase.Comp.GetTableHandle();
            testCase.verifyEqual(size(th.Data, 1), 4);

            testCase.selectRow(1);  % Click parent row again → collapse
            th = testCase.Comp.GetTableHandle();
            testCase.verifyEqual(size(th.Data, 1), 2, ...
                'Should collapse back to 2 rows');
        end

        function test_EmptyIndices_Noop(testCase)
            th = testCase.Comp.GetTableHandle();
            th.CellSelectionCallback(th, struct('Indices', []));
            pause(0.05);
            testCase.verifyEqual(size(th.Data, 1), 2, ...
                'Empty Indices should not change state');
        end

        %% ===== D2: Checkbox + Menu State Machine =====

        function test_CheckboxChild_On(testCase)
            testCase.expandDS();
            th = testCase.Comp.GetTableHandle();
            th.Data{2, 1} = true;

            cap = EventCapture();
            lh = addlistener(testCase.Comp, 'ActionRequested', ...
                @(~,e) cap.store(e));
            th.CellEditCallback(th, struct('Indices', [2, 1]));
            pause(0.05);

            testCase.verifyNotEmpty(cap.Events);
            p = cap.Events{1};
            testCase.verifyEqual(p.action, 'checkChanged');
            testCase.verifyEqual(p.datasetIdx, 1);
            testCase.verifyEqual(p.colIdx, 1);
            testCase.verifyTrue(p.checked);
            delete(lh);
        end

        function test_CheckboxChild_Off(testCase)
            testCase.expandDS();
            th = testCase.Comp.GetTableHandle();

            th.Data{2, 1} = true;
            th.CellEditCallback(th, struct('Indices', [2, 1]));
            pause(0.02);

            th.Data{2, 1} = false;
            cap = EventCapture();
            lh = addlistener(testCase.Comp, 'ActionRequested', ...
                @(~,e) cap.store(e));
            th.CellEditCallback(th, struct('Indices', [2, 1]));
            pause(0.05);

            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyFalse(cap.Events{1}.checked);
            delete(lh);
        end

        function test_Menu_ParentRow(testCase)
            testCase.selectRow(1);
            testCase.openContextMenu();
            cm = testCase.getContextMenu();

            testCase.assertMenuState(cm, '设置切片范围...',   'off');
            testCase.assertMenuState(cm, '切片重置',         'off');
            testCase.assertMenuState(cm, '设为横轴',         'off');
            testCase.assertMenuState(cm, '恢复默认横轴',     'off');
            testCase.assertMenuState(cm, '设为右 Y 轴',      'off');
            testCase.assertMenuState(cm, '恢复默认 Y 轴',    'off');
            testCase.assertMenuState(cm, '设置采样频率...',   'on');
            testCase.assertMenuState(cm, '导出 Excel',       'on');
        end

        function test_Menu_ChannelRow(testCase)
            testCase.expandDS();
            testCase.selectRow(2);
            testCase.openContextMenu();
            cm = testCase.getContextMenu();

            testCase.assertMenuState(cm, '设置切片范围...',   'on');
            testCase.assertMenuState(cm, '切片重置',         'on');
            testCase.assertMenuState(cm, '设为横轴',         'on');
            testCase.assertMenuState(cm, '恢复默认横轴',     'off');
            testCase.assertMenuState(cm, '设为右 Y 轴',      'on');
            testCase.assertMenuState(cm, '恢复默认 Y 轴',    'off');
            testCase.assertMenuState(cm, '设置采样频率...',   'off');
        end

        function test_Menu_XAxisChannel(testCase)
            testCase.expandDS();
            testCase.Comp.UpdateXChannel(1, 1);

            testCase.selectRow(2);
            testCase.openContextMenu();
            cm = testCase.getContextMenu();

            testCase.assertMenuState(cm, '设为横轴',     'off');  % already X
            testCase.assertMenuState(cm, '恢复默认横轴', 'on');
            testCase.assertMenuState(cm, '设为右 Y 轴',  'off');  % is X → no rightY
        end

        function test_Menu_RightYChannel(testCase)
            testCase.expandDS();
            testCase.Comp.UpdateRightY({[1, 2]});

            testCase.selectRow(3);  % ch2
            testCase.openContextMenu();
            cm = testCase.getContextMenu();

            testCase.assertMenuState(cm, '设为右 Y 轴',      'off');  % already rightY
            testCase.assertMenuState(cm, '恢复默认 Y 轴',    'on');
            testCase.assertMenuState(cm, '设为横轴',         'on');   % rightY ≠ X, can set X
        end

        %% ===== D3: Rename Behavior =====

        function test_RenameDataset(testCase)
            testCase.startRename(1);

            cap = EventCapture();
            lh = addlistener(testCase.Comp, 'ItemRenameRequested', ...
                @(~,e) cap.store(e));
            testCase.commitRename(1, 'RenamedDS');

            testCase.verifyNotEmpty(cap.Events);
            p = cap.Events{1};
            testCase.verifyEqual(p.action, 'rename');
            testCase.verifyTrue(p.isParent);
            testCase.verifyEqual(p.datasetIdx, 1);
            testCase.verifyEqual(p.newName, 'RenamedDS');
            delete(lh);
        end

        function test_RenameChannel(testCase)
            testCase.expandDS();
            testCase.startRename(2);

            cap = EventCapture();
            lh = addlistener(testCase.Comp, 'ItemRenameRequested', ...
                @(~,e) cap.store(e));
            testCase.commitRename(2, 'new_ch1');

            testCase.verifyNotEmpty(cap.Events);
            p = cap.Events{1};
            testCase.verifyEqual(p.action, 'rename');
            testCase.verifyFalse(p.isParent);
            testCase.verifyEqual(p.datasetIdx, 1);
            testCase.verifyEqual(p.colIdx, 1);
            testCase.verifyEqual(p.newName, 'new_ch1');
            delete(lh);
        end

        function test_RenameEmpty_Rollback(testCase)
        %Empty input should be rolled back (no event fires).
            testCase.startRename(1);

            cap = EventCapture();
            lh = addlistener(testCase.Comp, 'ItemRenameRequested', ...
                @(~,e) cap.store(e));
            testCase.commitRename(1, '   ');

            testCase.verifyEmpty(cap.Events, ...
                'Empty rename should be rolled back');
            delete(lh);
        end

        function test_RenameSame_NoEvent(testCase)
            testCase.startRename(1);

            cap = EventCapture();
            lh = addlistener(testCase.Comp, 'ItemRenameRequested', ...
                @(~,e) cap.store(e));
            testCase.commitRename(1, 'DS1');

            testCase.verifyEmpty(cap.Events, 'Same name should not fire');
            delete(lh);
        end

        function test_RenameDirtyInput_SelfHeals(testCase)
        %Garbage input with embedded tree chars is decoded by getCleanName.
            testCase.startRename(1);

            cap = EventCapture();
            lh = addlistener(testCase.Comp, 'ItemRenameRequested', ...
                @(~,e) cap.store(e));
            % User types messy input with tree decoration
            testCase.commitRename(1, '    ├─ RenamedDS  [X]');

            testCase.verifyNotEmpty(cap.Events, ...
                'Self-healing should decode and emit rename');
            p = cap.Events{1};
            testCase.verifyEqual(p.newName, 'RenamedDS');
            testCase.verifyEqual(p.oldName, 'DS1');
            delete(lh);
        end

        %% ===== D4: Menu Actions + Stress =====

        function test_Action_setSampleRate(testCase)
            testCase.runMenuAction(1, '设置采样频率...', 'setSampleRate', 1, 0);
        end

        function test_Action_exportExcel(testCase)
            testCase.runMenuAction(1, '导出 Excel', 'exportExcel', 1, 0);
        end

        function test_Action_slice(testCase)
            testCase.expandDS();
            testCase.runMenuAction(2, '设置切片范围...', 'slice', 1, 1);
        end

        function test_Action_sliceReset(testCase)
            testCase.expandDS();
            testCase.runMenuAction(2, '切片重置', 'sliceReset', 1, 1);
        end

        function test_Action_setXAxis(testCase)
            testCase.expandDS();
            testCase.runMenuAction(2, '设为横轴', 'setXAxis', 1, 1);
        end

        function test_Action_clearXAxis(testCase)
            testCase.expandDS();
            testCase.runMenuAction(2, '恢复默认横轴', 'clearXAxis', 0, 0);
        end

        function test_Action_setRightY(testCase)
            testCase.expandDS();
            testCase.runMenuAction(2, '设为右 Y 轴', 'setRightY', 1, 1);
        end

        function test_Action_clearRightY(testCase)
            testCase.expandDS();
            testCase.runMenuAction(2, '恢复默认 Y 轴', 'clearRightY', 0, 0);
        end

        function test_Stress_SetRows(testCase)
            for i = 1:100
                rows = struct( ...
                    'isParent',    {true,  false, true,  false}, ...
                    'datasetIdx',  {1,     1,     2,     2    }, ...
                    'colIdx',      {0,     1,     0,     1    }, ...
                    'label',       {'A',   'x',   'B',   'y'  }, ...
                    'datasetName', {'A',   'A',   'B',   'B'  }, ...
                    'checked',     {false, false, false, false});
                testCase.Comp.SetRows(rows);
            end
            th = testCase.Comp.GetTableHandle();
            testCase.verifyEqual(size(th.Data, 1), 2, ...
                'Final state should be 2 visible rows');
        end

        function test_Stress_Checkbox(testCase)
            testCase.expandDS();
            th = testCase.Comp.GetTableHandle();

            cap = EventCapture();
            lh = addlistener(testCase.Comp, 'ActionRequested', ...
                @(~,e) cap.store(e));

            for i = 1:100
                th.Data{2, 1} = logical(mod(i, 2));
                th.CellEditCallback(th, struct('Indices', [2, 1]));
            end
            pause(0.1);

            testCase.verifyNumElements(cap.Events, 100, ...
                'Expected 100 events from 100 checkbox toggles');
            delete(lh);
        end

        %% ===== D5: Exception Injection =====

        function test_EmptyVisibleRowMap_CellEditBlocked(testCase)
            testCase.Comp.SetRows([]);
            th = testCase.Comp.GetTableHandle();

            cap = EventCapture();
            lh = addlistener(testCase.Comp, 'ActionRequested', ...
                @(~,e) cap.store(e));

            % Manually inject data to trigger CellEditCallback
            % when VisibleRowMap is empty → guard should block
            th.Data = table(true, {'test'}, 'VariableNames', {'选择', '数据集'});
            th.CellEditCallback(th, struct('Indices', [1, 1]));
            pause(0.05);

            testCase.verifyEmpty(cap.Events, ...
                'CellEditCallback blocked when VisibleRowMap is empty');
            delete(lh);
        end

        function test_OutOfRangeVisRow_SilentReturn(testCase)
            testCase.expandDS();
            th = testCase.Comp.GetTableHandle();

            cap = EventCapture();
            lh = addlistener(testCase.Comp, 'ActionRequested', ...
                @(~,e) cap.store(e));

            th.Data{2, 1} = true;
            th.CellEditCallback(th, struct('Indices', [999, 1]));
            pause(0.05);

            testCase.verifyEmpty(cap.Events, ...
                'Out-of-range visRow should be a silent return');
            delete(lh);
        end
    end
end

%% ===== Local Functions =====

function rows = buildMockRows()
    rows = struct( ...
        'isParent',    {true,  false, false, true,  false}, ...
        'datasetIdx',  {1,     1,     1,     2,     2    }, ...
        'colIdx',      {0,     1,     2,     0,     1    }, ...
        'label',       {'DS1', 'ch1', 'ch2', 'DS2', 'A'  }, ...
        'datasetName', {'DS1', 'DS1', 'DS1', 'DS2', 'DS2'}, ...
        'checked',     {false, false, false, false, false});
end

function menuH = findMenuByText(cm, text)
    menuH = [];
    for i = 1:numel(cm.Children)
        if strcmp(cm.Children(i).Text, text)
            menuH = cm.Children(i);
            return
        end
    end
    error('findMenuByText:notFound', 'Menu "%s" not found', text);
end
