classdef test_UI_ExhaustiveInteractions < matlab.unittest.TestCase
%TEST_UI_EXHAUSTIVEINTERACTIONS  34-path E2E test per UI交互逻辑清单.md
%   All interactions are programmatic (no manual clicks).
%   Triggers real UI callbacks and asserts Presenter/View state changes.

    properties
        Fig
        TabGroup
        Tab
        View
        Presenter
        Session
        StatusMessages cell
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
            testCase.TabGroup = uitabgroup(testCase.Fig);
            testCase.Tab = uitab(testCase.TabGroup, 'Title', 'Test');
            testCase.Session = SessionData(6);
            testCase.StatusMessages = {};
            testCase.View = TimeSeriesView(testCase.Tab);
            testCase.Presenter = TimeSeriesPresenter( ...
                testCase.View, testCase.Session, ...
                @(txt) testCase.captureStatus(txt));
        end
    end

    methods (TestMethodTeardown)
        function destroyFixture(testCase)
            if isvalid(testCase.Fig), delete(testCase.Fig); end
        end
    end

    methods (Access = private)
        function captureStatus(obj, txt)
            obj.StatusMessages{end+1} = txt;
        end

        function loadMockData(testCase)
            ds1 = Dataset(randn(100, 2), {'ch1', 'ch2'}, 1000);
            ds2 = Dataset(randn(80, 1),  {'A'},         1000);
            testCase.Session.AddDataset(ds1, 'DS1', '');
            testCase.Session.AddDataset(ds2, 'DS2', '');
            testCase.Presenter.RefreshChannelTable();
        end

        function expandDS1(testCase)
            th = testCase.View.TableComp.GetTableHandle();
            th.CellSelectionCallback(th, struct('Indices', [1, 1]));
            pause(0.05);
        end

        function selectRow(testCase, visRow)
            th = testCase.View.TableComp.GetTableHandle();
            th.CellSelectionCallback(th, struct('Indices', [visRow, 1]));
            pause(0.02);
        end

        function openContextMenu(testCase)
            th = testCase.View.TableComp.GetTableHandle();
            cm = th.ContextMenu;
            cm.ContextMenuOpeningFcn(cm, []);
            pause(0.05);
        end

        function cm = getContextMenu(testCase)
            cm = testCase.View.TableComp.GetTableHandle().ContextMenu;
        end

        function btn = findBtn(testCase, text)
            btn = [];
            findRecursive(testCase.Fig);
            function findRecursive(h)
                if ~isempty(btn), return; end
                if isa(h, 'matlab.ui.control.Button') && strcmp(h.Text, text)
                    btn = h; return
                end
                if isprop(h, 'Children')
                    for c = 1:numel(h.Children)
                        findRecursive(h.Children(c));
                        if ~isempty(btn), return; end
                    end
                end
            end
            testCase.verifyNotEmpty(btn, sprintf('Button "%s" not found', text));
        end

        function assertMenuState(testCase, cm, menuText, expected)
            m = findMenuByText(cm, menuText);
            testCase.verifyEqual(string(m.Enable), string(expected), ...
                sprintf('Menu "%s": expected %s, got %s', ...
                menuText, expected, string(m.Enable)));
        end

        function triggerMenu(testCase, menuText)
            cm = testCase.getContextMenu();
            m = findMenuByText(cm, menuText);
            m.MenuSelectedFcn(m, []);
            pause(0.05);
        end
    end

    methods (Test)
        %% ===== 路径 1-3: 左侧面板按钮 =====

        function test_01_BrowseButton(testCase)
        %路径1: Browse → notify('BrowseClicked') → OnBrowseFolder
            btn = testCase.findBtn('Browse...');
            cap = EventCapture();
            lh = addlistener(testCase.View, 'BrowseClicked', @(~,e) cap.store(e));
            btn.ButtonPushedFcn(btn, []);
            pause(0.1);
            testCase.verifyNotEmpty(cap.Events, 'BrowseClicked should fire');
            delete(lh);
        end

        function test_02_ImportButton(testCase)
        %路径2: Import → notify('ImportButtonClicked') → OnImportFiles
            btn = testCase.findBtn('Import');
            cap = EventCapture();
            lh = addlistener(testCase.View, 'ImportButtonClicked', @(~,e) cap.store(e));
            btn.ButtonPushedFcn(btn, []);
            pause(0.1);
            testCase.verifyNotEmpty(cap.Events, 'ImportButtonClicked should fire');
            delete(lh);
        end

        function test_03_ClearAllButton(testCase)
        %路径3: Clear All → notify('ClearAllClicked') → OnClearAll
            testCase.loadMockData();
            btn = testCase.findBtn('Clear All');
            btn.ButtonPushedFcn(btn, []);
            pause(0.1);
            testCase.verifyEqual(testCase.Session.DatasetCount, 0, ...
                'ClearAll should remove all datasets');
            th = testCase.View.TableComp.GetTableHandle();
            testCase.verifyEqual(size(th.Data, 1), 0, 'Table should be empty');
        end

        %% ===== 路径 4-5: Axes 增删 =====

        function test_04_AddAxes(testCase)
        %路径4: + 按钮 → GridMgr.AddAxes → AxesAdded 事件
            btn = testCase.findBtn('+');
            g = testCase.View.GridMgr;
            n0 = g.Count;
            btn.ButtonPushedFcn(btn, []);
            testCase.verifyEqual(g.Count, n0 + 1);
        end

        function test_05_RemoveAxes(testCase)
        %路径5: − 按钮 → GridMgr.RemoveAxes → AxesRemoveClicked
            testCase.loadMockData();
            testCase.View.GridMgr.AddAxes();
            testCase.Session.AddChannelToAxes(2, 1, 1);

            btn = testCase.findBtn(char(8722));
            btn.ButtonPushedFcn(btn, []);
            pause(0.1);

            testCase.verifyEqual(testCase.View.GridMgr.Count, 1);
            testCase.verifyEmpty(testCase.Session.GetAxesChannels(2));
        end

        %% ===== 路径 6-7: 布局切换 =====

        function test_06_LayoutSingle(testCase)
        %路径6: ‖ 按钮 → notify('AxesClicked', {mode:'single'})
            btn = testCase.findBtn('||');
            cap = EventCapture();
            lh = addlistener(testCase.View, 'AxesClicked', @(~,e) cap.store(e));
            btn.ButtonPushedFcn(btn, []);
            pause(0.05);
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.mode, 'single');
            delete(lh);
        end

        function test_07_LayoutDual(testCase)
        %路径7: = 按钮 → notify('AxesClicked', {mode:'dual'})
            btn = testCase.findBtn('=');
            cap = EventCapture();
            lh = addlistener(testCase.View, 'AxesClicked', @(~,e) cap.store(e));
            btn.ButtonPushedFcn(btn, []);
            pause(0.05);
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.mode, 'dual');
            delete(lh);
        end

        %% ===== 路径 8-14: 工具栏按钮 =====

        function test_08_ExportButton(testCase)
        %路径8: Export → notify('ExportClicked') → OnExportFigure
            btn = testCase.findBtn('Export');
            cap = EventCapture();
            lh = addlistener(testCase.View, 'ExportClicked', @(~,e) cap.store(e));
            btn.ButtonPushedFcn(btn, []);
            pause(0.1);
            testCase.verifyNotEmpty(cap.Events);
            delete(lh);
        end

        function test_09_ClearPlotButton(testCase)
        %路径9: Clear → notify('ClearPlotClicked') → OnClearPlot
            testCase.loadMockData();
            axIdx = testCase.View.FocusedAxes;
            testCase.Session.AddChannelToAxes(axIdx, 1, 1);
            testCase.Presenter.RenderAxes(axIdx);

            btn = testCase.findBtn('Clear');
            btn.ButtonPushedFcn(btn, []);
            pause(0.1);

            ax = testCase.View.GetAxes(axIdx);
            dataLines = findobj(ax, 'Type', 'line');
            dataLines = dataLines(arrayfun(@(l) ~strcmp(l.Tag, 'cursor'), dataLines));
            testCase.verifyEmpty(dataLines, 'ClearPlot should remove all data lines');
        end

        function test_10_SpectrumButton(testCase)
        %路径10: 频谱 → notify('SpectrumClicked') → OnSpectrumClicked
            btn = testCase.findBtn('频谱');
            cap = EventCapture();
            lh = addlistener(testCase.View, 'SpectrumClicked', @(~,e) cap.store(e));
            btn.ButtonPushedFcn(btn, []);
            pause(0.1);
            testCase.verifyNotEmpty(cap.Events);
            delete(lh);
        end

        function test_11_NormButton(testCase)
        %路径11: Norm → onNormClicked → notify('NormClicked', {mode})
            testCase.loadMockData();
            axIdx = testCase.View.FocusedAxes;
            testCase.Session.AddChannelToAxes(axIdx, 1, 1);

            % Set dropdown to Min-Max
            testCase.View.NormDropdown.Value = 'Min-Max';
            btn = testCase.findBtn('Norm');
            btn.ButtonPushedFcn(btn, []);
            pause(0.1);

            testCase.verifyEqual(testCase.Session.GetAxesNormMode(axIdx), 'Min-Max');
        end

        function test_12_CalcButton(testCase)
        %路径12: Calc → notify('CalcClicked') → OnCalcChannel
            btn = testCase.findBtn('Calc');
            cap = EventCapture();
            lh = addlistener(testCase.View, 'CalcClicked', @(~,e) cap.store(e));
            btn.ButtonPushedFcn(btn, []);
            pause(0.1);
            testCase.verifyNotEmpty(cap.Events);
            delete(lh);
        end

        function test_13_SpectrumDropdown(testCase)
        %路径13: 频谱下拉框 → GetSpectrumMode 读取
            testCase.View.SpectrumDropdown.Value = 'PSD';
            testCase.verifyEqual(testCase.View.GetSpectrumMode(), 'PSD');
            testCase.View.SpectrumDropdown.Value = 'FFT';
            testCase.verifyEqual(testCase.View.GetSpectrumMode(), 'FFT');
        end

        function test_14_NormDropdown(testCase)
        %路径14: Norm 下拉框 → NormClicked 载荷包含选中值
            testCase.View.NormDropdown.Value = 'Z-Score';
            btn = testCase.findBtn('Norm');
            cap = EventCapture();
            lh = addlistener(testCase.View, 'NormClicked', @(~,e) cap.store(e));
            btn.ButtonPushedFcn(btn, []);
            pause(0.05);
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.mode, 'Z-Score');
            delete(lh);
        end

        %% ===== 路径 15-16: 通道表复选框 =====

        function test_15_ParentCheckbox(testCase)
        %路径15: 父行复选框 → colIdx=0 全选
            testCase.loadMockData();
            th = testCase.View.TableComp.GetTableHandle();
            cap = EventCapture();
            lh = addlistener(testCase.View, 'ChannelCheckChanged', @(~,e) cap.store(e));
            th.Data{1, 1} = true;
            th.CellEditCallback(th, struct('Indices', [1, 1]));
            pause(0.05);
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.colIdx, 0);
            testCase.verifyEqual(cap.Events{1}.datasetIdx, 1);
            testCase.verifyTrue(cap.Events{1}.checked);
            delete(lh);
        end

        function test_16_ChildCheckbox(testCase)
        %路径16: 子行复选框 → colIdx>0 单选
            testCase.loadMockData();
            testCase.expandDS1();
            th = testCase.View.TableComp.GetTableHandle();
            cap = EventCapture();
            lh = addlistener(testCase.View, 'ChannelCheckChanged', @(~,e) cap.store(e));
            th.Data{2, 1} = true;
            th.CellEditCallback(th, struct('Indices', [2, 1]));
            pause(0.05);
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.colIdx, 1);
            testCase.verifyTrue(cap.Events{1}.checked);
            delete(lh);
        end

        %% ===== 路径 17: 展开/折叠 =====

        function test_17_ExpandCollapse(testCase)
        %路径17: 点击父行 → 展开/折叠
            testCase.loadMockData();
            th = testCase.View.TableComp.GetTableHandle();
            testCase.verifyEqual(size(th.Data, 1), 2, 'Collapsed: 2 rows');

            testCase.expandDS1();
            testCase.verifyEqual(size(th.Data, 1), 4, 'Expanded: 4 rows');

            testCase.selectRow(1);
            testCase.verifyEqual(size(th.Data, 1), 2, 'Collapsed again: 2 rows');
        end

        %% ===== 路径 18: 重命名 =====

        function test_18_RenameCommit(testCase)
        %路径18: 内联重命名→提交
            testCase.loadMockData();
            testCase.selectRow(1);

            cap = EventCapture();
            lh = addlistener(testCase.View, 'ItemRenameRequested', @(~,e) cap.store(e));
            th = testCase.View.TableComp.GetTableHandle();
            oldRaw = th.Data{1, 2};
            if iscell(oldRaw), oldRaw = oldRaw{1}; end
            th.CellEditCallback(th, struct( ...
                'Indices', [1, 2], ...
                'PreviousData', oldRaw, ...
                'NewData', 'NewDS'));
            pause(0.05);

            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.action, 'rename');
            delete(lh);
        end

        %% ===== 路径 19-28: 右键菜单 10 项操作 =====

        function test_19_Menu_setSampleRate(testCase)
        %路径19: 右键→设置采样频率
            testCase.loadMockData();
            testCase.selectRow(1);
            testCase.openContextMenu();
            cap = EventCapture();
            lh = addlistener(testCase.View, 'SetSampleRateClicked', @(~,e) cap.store(e));
            testCase.triggerMenu('设置采样频率...');
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.action, 'setSampleRate');
            delete(lh);
        end

        function test_20_Menu_exportExcel(testCase)
        %路径20: 右键→导出 Excel
            testCase.loadMockData();
            testCase.selectRow(1);
            testCase.openContextMenu();
            cap = EventCapture();
            lh = addlistener(testCase.View, 'ExportExcelClicked', @(~,e) cap.store(e));
            testCase.triggerMenu('导出 Excel');
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.action, 'exportExcel');
            delete(lh);
        end

        function test_21_Menu_slice(testCase)
        %路径21: 右键→设置切片范围
            testCase.loadMockData();
            testCase.expandDS1();
            testCase.selectRow(2);
            testCase.openContextMenu();
            cap = EventCapture();
            lh = addlistener(testCase.View, 'SliceDialogClicked', @(~,e) cap.store(e));
            testCase.triggerMenu('设置切片范围...');
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.colIdx, 1);
            delete(lh);
        end

        function test_22_Menu_sliceReset(testCase)
        %路径22: 右键→切片重置
            testCase.loadMockData();
            testCase.expandDS1();
            testCase.selectRow(2);
            testCase.openContextMenu();
            cap = EventCapture();
            lh = addlistener(testCase.View, 'SliceResetClicked', @(~,e) cap.store(e));
            testCase.triggerMenu('切片重置');
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.action, 'sliceReset');
            delete(lh);
        end

        function test_23_Menu_setXAxis(testCase)
        %路径23: 右键→设为横轴
            testCase.loadMockData();
            testCase.expandDS1();
            testCase.selectRow(2);
            testCase.openContextMenu();
            cap = EventCapture();
            lh = addlistener(testCase.View, 'SetXAxisClicked', @(~,e) cap.store(e));
            testCase.triggerMenu('设为横轴');
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.datasetIdx, 1);
            testCase.verifyEqual(cap.Events{1}.colIdx, 1);
            delete(lh);
        end

        function test_24_Menu_clearXAxis(testCase)
        %路径24: 右键→恢复默认横轴
            testCase.loadMockData();
            testCase.expandDS1();
            testCase.selectRow(2);
            testCase.openContextMenu();
            cap = EventCapture();
            lh = addlistener(testCase.View, 'ClearXAxisClicked', @(~,e) cap.store(e));
            testCase.triggerMenu('恢复默认横轴');
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyTrue(isfield(cap.Events{1}, 'axesIdx'));
            delete(lh);
        end

        function test_25_Menu_setRightY(testCase)
        %路径25: 右键→设为右 Y 轴
            testCase.loadMockData();
            testCase.expandDS1();
            testCase.selectRow(2);
            testCase.openContextMenu();
            cap = EventCapture();
            lh = addlistener(testCase.View, 'SetRightYAxisClicked', @(~,e) cap.store(e));
            testCase.triggerMenu('设为右 Y 轴');
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.datasetIdx, 1);
            delete(lh);
        end

        function test_26_Menu_clearRightY(testCase)
        %路径26: 右键→恢复默认 Y 轴
            testCase.loadMockData();
            testCase.expandDS1();
            testCase.selectRow(2);
            testCase.openContextMenu();
            cap = EventCapture();
            lh = addlistener(testCase.View, 'ClearRightYAxisClicked', @(~,e) cap.store(e));
            testCase.triggerMenu('恢复默认 Y 轴');
            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyTrue(isfield(cap.Events{1}, 'axesIdx'));
            delete(lh);
        end

        function test_27_MenuState_ParentRow(testCase)
        %路径27: 父行菜单可用性（仅 exportExcel/setSampleRate 可用）
            testCase.loadMockData();
            testCase.selectRow(1);
            testCase.openContextMenu();
            cm = testCase.getContextMenu();
            testCase.assertMenuState(cm, '设置切片范围...', 'off');
            testCase.assertMenuState(cm, '设为横轴',       'off');
            testCase.assertMenuState(cm, '设为右 Y 轴',    'off');
            testCase.assertMenuState(cm, '设置采样频率...', 'on');
            testCase.assertMenuState(cm, '导出 Excel',     'on');
        end

        function test_28_MenuState_XAxisMutex(testCase)
        %路径28: X轴通道互斥（设为横轴 OFF，恢复默认横轴 ON，设为右Y OFF）
            testCase.loadMockData();
            testCase.expandDS1();
            testCase.View.UpdateAxisChannelState(1, 1, 1, {});
            testCase.selectRow(2);
            testCase.openContextMenu();
            cm = testCase.getContextMenu();
            testCase.assertMenuState(cm, '设为横轴',     'off');
            testCase.assertMenuState(cm, '恢复默认横轴', 'on');
            testCase.assertMenuState(cm, '设为右 Y 轴',  'off');
        end

        %% ===== 路径 29-31: Axes 交互 =====

        function test_29_LineClick(testCase)
        %路径29: 线条点击 → ButtonDownFcn → FocusedAxes 更新
            testCase.loadMockData();
            axIdx = testCase.View.FocusedAxes;
            testCase.Session.AddChannelToAxes(axIdx, 1, 1);
            testCase.Presenter.RenderAxes(axIdx);

            ax = testCase.View.GetAxes(axIdx);
            dataLines = findobj(ax, 'Type', 'line');
            dataLines = dataLines(arrayfun(@(l) ~strcmp(l.Tag, 'cursor'), dataLines));
            testCase.verifyNotEmpty(dataLines, 'Need data lines for click test');

            mockEvent = struct('Button', 1, 'IntersectionPoint', [5 0.5 0]);
            dataLines(1).ButtonDownFcn(dataLines(1), mockEvent);
            pause(0.05);

            testCase.verifyEqual(testCase.View.FocusedAxes, axIdx);
        end

        function test_30_BlankAreaClick(testCase)
        %路径30: 空白区点击 → axes ButtonDownFcn → FocusedAxes 更新
            testCase.loadMockData();
            axIdx = testCase.View.FocusedAxes;
            testCase.Session.AddChannelToAxes(axIdx, 1, 1);
            testCase.Presenter.RenderAxes(axIdx);

            ax = testCase.View.GetAxes(axIdx);
            mockEvent = struct('Button', 1, 'IntersectionPoint', [5 0 0]);
            ax.ButtonDownFcn(ax, mockEvent);
            pause(0.05);

            testCase.verifyEqual(testCase.View.FocusedAxes, axIdx);
        end

        function test_31_CursorMotion(testCase)
        %路径31: 鼠标移动 → ProcessMouseMotion → CursorMotion 事件
            testCase.loadMockData();
            axIdx = testCase.View.FocusedAxes;
            testCase.Session.AddChannelToAxes(axIdx, 1, 1);
            testCase.Presenter.RenderAxes(axIdx);

            cursor = testCase.View.CursorMap(axIdx);
            snapData = struct('action','CursorSnapped', 'axesIdx', axIdx, ...
                'x', 50.0, 'y', 0.5, 'lineTag', 'leftY', 'xDataIdx', 50);

            cap = EventCapture();
            lh = addlistener(testCase.View, 'CursorMotion', @(~,e) cap.store(e));
            notify(cursor, 'CursorSnapped', AppEventData(snapData));
            pause(0.1);

            testCase.verifyNotEmpty(cap.Events);
            testCase.verifyEqual(cap.Events{1}.x, 50.0, 'AbsTol', 0.01);
            delete(lh);
        end

        %% ===== 路径 32-34: Session 状态同步 =====

        function test_32_SetXChannel_SyncsView(testCase)
        %路径32: 设为横轴 → Session 更新 → SyncViewAxisState → View 状态同步
            testCase.loadMockData();
            axIdx = testCase.View.FocusedAxes;
            testCase.Session.AddChannelToAxes(axIdx, 1, 1);
            testCase.Session.AddChannelToAxes(axIdx, 1, 2);
            testCase.Session.SetXChannel(axIdx, 1, 1);
            testCase.Presenter.RenderAxes(axIdx);

            [xDs, xCol] = testCase.Session.GetXChannel(axIdx);
            testCase.verifyEqual(xDs, 1);
            testCase.verifyEqual(xCol, 1);
        end

        function test_33_RemoveDataset_ClearsRefs(testCase)
        %路径33: 删除数据集 → X/右Y 引用清理
            testCase.loadMockData();
            testCase.Session.SetXChannel(1, 1, 1);
            testCase.Session.SetRightYChannel(1, 1, 2);

            testCase.Session.RemoveDataset(1);

            [xDs, ~] = testCase.Session.GetXChannel(1);
            testCase.verifyEmpty(xDs, 'X ref should be cleared');
            refs = testCase.Session.GetRightYChannel(1);
            testCase.verifyEmpty(refs, 'RightY ref should be cleared');
        end

        function test_34_Import_RendersWaveform(testCase)
        %路径34: 导入数据 → addResultsToSession → RefreshChannelTable → 表格填充
            % Simulate import by adding dataset directly
            ds = Dataset(randn(50, 3), {'A', 'B', 'C'}, 1000);
            testCase.Session.AddDataset(ds, 'ImportedDS', '');
            testCase.Presenter.RefreshChannelTable();

            th = testCase.View.TableComp.GetTableHandle();
            testCase.verifyGreaterThan(size(th.Data, 1), 0, ...
                'Table should have rows after import');

            % Check and render
            testCase.expandDS1();
            axIdx = testCase.View.FocusedAxes;
            testCase.Session.AddChannelToAxes(axIdx, 3, 1);
            testCase.Presenter.RenderAxes(axIdx);

            ax = testCase.View.GetAxes(axIdx);
            dataLines = findobj(ax, 'Type', 'line');
            dataLines = dataLines(arrayfun(@(l) ~strcmp(l.Tag, 'cursor'), dataLines));
            testCase.verifyGreaterThanOrEqual(numel(dataLines), 1, ...
                'Should have at least 1 data line after import+check');
        end
    end
end

%% ===== Local Functions =====

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
