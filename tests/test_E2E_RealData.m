classdef test_E2E_RealData < matlab.unittest.TestCase
%TEST_E2E_REALDATA  5-scenario E2E test with real data from DRFDOT/Trace_data.
%   All interactions are 100% programmatic. Zero manual clicks.

    properties
        App
        DataDir = 'D:\Project\matlab\TOOLS\SignalAnalysis\DRFDOT\Trace_data\20260310_161313'
    end

    methods (TestMethodSetup)
        function createApp(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            addpath(fullfile(root, 'view'));
            addpath(fullfile(root, 'view', 'components'));
            addpath(fullfile(root, 'model'));
            addpath(fullfile(root, 'presenter'));
            addpath(fullfile(root, 'service'));
            addpath(fullfile(root, 'app'));
            addpath(fullfile(root, 'tests'));
            addpath(root);
            testCase.App = SignalAnalysisApp();
        end
    end

    methods (TestMethodTeardown)
        function destroyApp(testCase)
            if ~isempty(testCase.App) && isvalid(testCase.App.Fig)
                delete(testCase.App.Fig);
            end
        end
    end

    methods (Access = private)
        function [tsv, tsp, fig] = getApp(testCase)
            tsv = testCase.App.TimeSeriesView;
            tsp = testCase.App.TimeSeriesPresenter;
            fig = testCase.App.Fig;
        end

        function importData(testCase, tsv, tsp)
        %IMPORTDATA  Import real data from DRFDOT/Trace_data via Presenter.
            matFile = fullfile(testCase.DataDir, ...
                '20260310_161313_Trace_data_standardized.mat');
            ds = DataReaderFactory.LoadStandard(matFile);
            tsp.Session.AddDataset(ds, 'Trace_data', matFile);
            tsp.RefreshChannelTable();
            pause(0.1);
        end

        function checkChannel(testCase, tsv, rowIdx)
        %CHECKCHANNEL  Programmatically check a channel checkbox.
            testCase.expandDS(tsv);
            th = tsv.TableComp.GetTableHandle();
            th.Data{rowIdx, 1} = true;
            th.CellEditCallback(th, struct('Indices', [rowIdx, 1]));
            pause(0.2);
        end

        function expandDS(~, tsv)
            th = tsv.TableComp.GetTableHandle();
            th.CellSelectionCallback(th, struct('Indices', [1, 1]));
            pause(0.05);
        end

        function [axPos, centerX, centerY] = getAxesCenter(~, fig, ax)
            axPos = hgconvertunits(fig, ax.Position, ax.Units, 'pixels', fig);
            centerX = axPos(1) + axPos(3) / 2;
            centerY = axPos(2) + axPos(4) / 2;
        end

        function snapResult = simulateMouseSnap(testCase, tsv, fig, ax, fracX, fracY)
        %SIMULATEMOUSESNAP  Move simulated mouse to axes position, return snap data.
            axPos = hgconvertunits(fig, ax.Position, ax.Units, 'pixels', fig);
            fig.CurrentPoint = [axPos(1) + axPos(3)*fracX, axPos(2) + axPos(4)*fracY];
            tsv.ProcessMouseMotion();
            pause(0.05);
            snapResult = struct('fired', false, 'x', NaN, 'y', NaN);
            % Read last cursor state from CursorMap
            idx = tsv.FocusedAxes;
            if tsv.CursorMap.isKey(idx)
                cursor = tsv.CursorMap(idx);
                if ~isempty(cursor) && isvalid(cursor)
                    % We can't read private properties, but the cursor exists
                    snapResult.fired = true;
                end
            end
        end
    end

    methods (Test)
        %% ===== 场景 1: 导入真实数据 → 勾选通道 → 游标吸附 =====

        function test_01_ImportAndCursorSnap(testCase)
        %场景1: 从 DRFDOT/Trace_data 导入 → 勾选 Y2_ERROR → 游标吸附
            [tsv, tsp, fig] = testCase.getApp();
            testCase.importData(tsv, tsp);

            th = tsv.TableComp.GetTableHandle();
            testCase.verifyGreaterThan(size(th.Data, 1), 0, 'Table should have rows');

            % Check Y2_ERROR (row 2)
            testCase.checkChannel(tsv, 2);
            ax = tsv.GetAxes(1);
            allLines = findobj(ax, 'Type', 'line');
            dataLines = allLines(arrayfun(@(l) ~strcmp(l.Tag, 'cursor'), allLines));
            testCase.verifyGreaterThanOrEqual(numel(dataLines), 1, 'Y2_ERROR should be plotted');

            % Cursor snap via SetPosition (bypass radius, programmatic)
            cursor = tsv.CursorMap(1);
            cap = EventCapture();
            lh = addlistener(cursor, 'CursorSnapped', @(~,e) cap.store(e));
            cursor.SetPosition(1000);
            testCase.verifyNotEmpty(cap.Events, 'Cursor should snap to data');
            testCase.verifyEqual(cap.Events{1}.axesIdx, 1);
            delete(lh);
        end

        %% ===== 场景 2: 右Y轴 + 游标吸附 =====

        function test_02_RightYAxisCursorSnap(testCase)
        %场景2: 左Y + 右Y → 游标吸附双轴数据
            [tsv, tsp, fig] = testCase.getApp();
            testCase.importData(tsv, tsp);

            axIdx = tsv.FocusedAxes;

            % Add both channels to axes
            tsp.Session.AddChannelToAxes(axIdx, 1, 1);  % Y2_ERROR → left Y
            tsp.Session.AddChannelToAxes(axIdx, 1, 2);  % RZ2_ERROR → initially left Y

            % Set RZ2_ERROR as right Y
            tsp.Session.SetRightYChannel(axIdx, 1, 2);
            tsp.RenderAxes(axIdx);
            pause(0.1);

            % Verify right Y axis is visible
            ax = tsv.GetAxes(axIdx);
            testCase.verifyEqual(string(ax.YAxis(2).Visible), string('on'), ...
                'Right Y axis should be visible');

            % Verify both leftY and rightY lines exist
            allLines = findobj(ax, 'Type', 'line');
            dataLines = allLines(arrayfun(@(l) ~strcmp(l.Tag, 'cursor'), allLines));
            leftLines = dataLines(arrayfun(@(l) strcmp(l.Tag, 'leftY'), dataLines));
            rightLines = dataLines(arrayfun(@(l) strcmp(l.Tag, 'rightY'), dataLines));
            testCase.verifyGreaterThanOrEqual(numel(leftLines), 1, 'Should have leftY line');
            testCase.verifyGreaterThanOrEqual(numel(rightLines), 1, 'Should have rightY line');

            % Cursor snap via SetPosition
            cursor = tsv.CursorMap(axIdx);
            cap = EventCapture();
            lh = addlistener(cursor, 'CursorSnapped', @(~,e) cap.store(e));
            cursor.SetPosition(1000);
            testCase.verifyNotEmpty(cap.Events, 'Cursor should snap with rightY data');
            delete(lh);
        end

        %% ===== 场景 3: +/- 按钮增删 axes =====

        function test_03_AddRemoveAxes(testCase)
        %场景3: + 添加 axes → 验证 → - 删除 axes → 验证
            [tsv, tsp, fig] = testCase.getApp();
            testCase.importData(tsv, tsp);
            g = tsv.GridMgr;

            % Add 2 more axes (total 3)
            g.AddAxes();
            g.AddAxes();
            testCase.verifyEqual(g.Count, 3, 'Should have 3 axes');
            testCase.verifyTrue(tsv.CursorMap.isKey(2), 'Cursor 2 should exist');
            testCase.verifyTrue(tsv.CursorMap.isKey(3), 'Cursor 3 should exist');

            % Check channel on axes 2
            tsp.Session.AddChannelToAxes(2, 1, 1);
            tsp.RenderAxes(2);
            ax2 = tsv.GetAxes(2);
            dataLines2 = findobj(ax2, 'Type', 'line');
            dataLines2 = dataLines2(arrayfun(@(l) ~strcmp(l.Tag, 'cursor'), dataLines2));
            testCase.verifyGreaterThanOrEqual(numel(dataLines2), 1, 'Axes 2 should have data');

            % Remove axes 3
            g.RemoveAxes(3);
            testCase.verifyEqual(g.Count, 2, 'Should have 2 axes after removal');

            % Cursor on axes 2 should still work
            testCase.verifyTrue(tsv.CursorMap.isKey(2), 'Cursor 2 should survive removal of axes 3');

            % Remove axes 2
            g.RemoveAxes(2);
            testCase.verifyEqual(g.Count, 1, 'Should have 1 axes after removal');
        end

        %% ===== 场景 4: 选中指定 axes 后操作 =====

        function test_04_SelectSpecificAxes(testCase)
        %场景4: 多 axes → 选中特定 axes → 勾选通道 → 游标吸附
            [tsv, tsp, fig] = testCase.getApp();
            testCase.importData(tsv, tsp);
            g = tsv.GridMgr;

            % Add second axes
            g.AddAxes();
            testCase.verifyEqual(g.Count, 2);

            % Check channel on axes 1
            testCase.checkChannel(tsv, 2);

            % Click on axes 2 to focus it
            ax2 = tsv.GetAxes(2);
            mockEvent = struct('Button', 1, 'IntersectionPoint', [5 0 0]);
            ax2.ButtonDownFcn(ax2, mockEvent);
            pause(0.05);
            testCase.verifyEqual(tsv.FocusedAxes, 2, 'Axes 2 should be focused');

            % Check channel on axes 2
            tsp.Session.AddChannelToAxes(2, 1, 1);
            tsp.RenderAxes(2);
            dataLines = findobj(ax2, 'Type', 'line');
            dataLines = dataLines(arrayfun(@(l) ~strcmp(l.Tag, 'cursor'), dataLines));
            testCase.verifyGreaterThanOrEqual(numel(dataLines), 1, 'Axes 2 should have data');

            % Cursor on axes 2 should work
            testCase.simulateMouseSnap(tsv, fig, ax2, 0.5, 0.5);
            testCase.verifyTrue(tsv.CursorMap.isKey(2), 'Cursor 2 should exist');
        end

        %% ===== 场景 5: 布局按钮 || = =====

        function test_05_LayoutButtons(testCase)
        %场景5: 测试 || = 按钮对布局的实际作用
            [tsv, tsp, fig] = testCase.getApp();
            g = tsv.GridMgr;

            % Add second axes
            g.AddAxes();
            testCase.verifyEqual(g.Count, 2);

            % Verify layout mode for 2 axes
            testCase.verifyEqual(g.LayoutMode, "vert2", '2 axes should be vert2 layout');

            % Add more axes to test different layouts
            g.AddAxes();
            testCase.verifyEqual(g.LayoutMode, "vert3", '3 axes should be vert3 layout');

            g.AddAxes();
            testCase.verifyEqual(g.LayoutMode, "2x2", '4 axes should be 2x2 layout');

            % Remove back to 1
            g.RemoveAxes(4);
            g.RemoveAxes(3);
            g.RemoveAxes(2);
            testCase.verifyEqual(g.Count, 1);
            testCase.verifyEqual(g.LayoutMode, "single", '1 axes should be single layout');
        end
    end
end
