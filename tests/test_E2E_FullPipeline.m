classdef test_E2E_FullPipeline < matlab.unittest.TestCase
%TEST_E2E_FULLPIPELINE  Zero-manual-click E2E test: StartApp → Import → Check → Mouse → Cursor.
%   Simulates the FULL real app flow programmatically.
%   No physical mouse, no visible UI, no human interaction required.

    properties
        App
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

    methods (Test)
        function test_FullPipeline(testCase)
        %Full pipeline: import data → check channel → simulate mouse → verify cursor snap.
        %   Zero manual clicks. All interactions are programmatic.

            app = testCase.App;
            tsv = app.TimeSeriesView;
            tsp = app.TimeSeriesPresenter;

            %% Step 1: Verify app construction
            testCase.verifyEqual(tsv.GridMgr.Count, 1, 'Should have 1 axes');
            testCase.verifyTrue(tsv.CursorMap.isKey(1), 'Cursor should exist');

            %% Step 2: Simulate import (add dataset directly to Session)
            ds = Dataset(randn(200, 2), {'ch1', 'ch2'}, 1000);
            tsp.Session.AddDataset(ds, 'TestDS', '');
            tsp.RefreshChannelTable();

            % Verify table populated
            th = tsv.TableComp.GetTableHandle();
            testCase.verifyGreaterThan(size(th.Data, 1), 0, 'Table should have rows');

            %% Step 3: Simulate checkbox (check ch1)
            testCase.expandDS(tsv);
            th = tsv.TableComp.GetTableHandle();
            cap = EventCapture();
            lh = addlistener(tsv, 'ChannelCheckChanged', @(~,e) cap.store(e));
            th.Data{2, 1} = true;
            th.CellEditCallback(th, struct('Indices', [2, 1]));
            pause(0.1);
            testCase.verifyNotEmpty(cap.Events, 'ChannelCheckChanged should fire');
            testCase.verifyEqual(cap.Events{1}.colIdx, 1);
            delete(lh);

            %% Step 4: Verify data rendered on axes
            ax = tsv.GetAxes(1);
            dataLines = findobj(ax, 'Type', 'line');
            dataLines = dataLines(arrayfun(@(l) ~strcmp(l.Tag, 'cursor'), dataLines));
            testCase.verifyGreaterThanOrEqual(numel(dataLines), 1, ...
                'At least 1 data line should be plotted');

            %% Step 5: Cursor snap via SetPosition (programmatic, bypass radius)
            cursor = tsv.CursorMap(1);
            capCursor = EventCapture();
            lh2 = addlistener(cursor, 'CursorSnapped', @(~,e) capCursor.store(e));
            cursor.SetPosition(100);
            testCase.verifyNotEmpty(capCursor.Events, 'Cursor should snap to data');
            testCase.verifyEqual(capCursor.Events{1}.axesIdx, 1);
            delete(lh2);

            %% Step 6: Cursor snaps at different X positions
            capMulti = EventCapture();
            lh3 = addlistener(cursor, 'CursorSnapped', @(~,e) capMulti.store(e));
            for xPos = [50, 100, 150]
                cursor.SetPosition(xPos);
            end
            testCase.verifyNumElements(capMulti.Events, 3, ...
                'Cursor should snap at each X position');
            delete(lh3);
                %% Step 7: Verify cursor X changes with different positions
            testCase.verifyNotEqual(capMulti.Events{1}.x, capMulti.Events{end}.x, ...
                'Cursor X should change at different positions');
        end

        function test_RenderWaveform_PreservesCursor(testCase)
        %Verify that RenderWaveform does not destroy cursor objects.
            app = testCase.App;
            tsv = app.TimeSeriesView;
            tsp = app.TimeSeriesPresenter;

            % Add data and render
            ds = Dataset(randn(100, 2), {'A', 'B'}, 1000);
            tsp.Session.AddDataset(ds, 'DS', '');
            tsp.RefreshChannelTable();
            tsp.Session.AddChannelToAxes(1, 1, 1);
            tsp.RenderAxes(1);

            % Cursor should still be valid
            testCase.verifyTrue(tsv.CursorMap.isKey(1), 'Cursor should survive render');

            % Render again (simulates re-check)
            tsp.Session.AddChannelToAxes(1, 1, 2);
            tsp.RenderAxes(1);

            % Cursor should STILL be valid
            testCase.verifyTrue(tsv.CursorMap.isKey(1), ...
                'Cursor should survive multiple renders');

            % Snap should work after render
            cursor = tsv.CursorMap(1);
            cap = EventCapture();
            lh = addlistener(cursor, 'CursorSnapped', @(~,e) cap.store(e));
            cursor.SetPosition(50);
            testCase.verifyNotEmpty(cap.Events, ...
                'Cursor should snap after RenderWaveform');
            delete(lh);
        end

        function test_ClearAndReRender(testCase)
        %Clear plot then re-render: cursor should still work.
            app = testCase.App;
            tsv = app.TimeSeriesView;
            tsp = app.TimeSeriesPresenter;

            ds = Dataset(randn(100, 1), {'X'}, 1000);
            tsp.Session.AddDataset(ds, 'DS', '');
            tsp.RefreshChannelTable();
            tsp.Session.AddChannelToAxes(1, 1, 1);
            tsp.RenderAxes(1);

            % Clear
            notify(tsv, 'ClearPlotClicked');
            pause(0.1);

            % Re-render
            tsp.Session.AddChannelToAxes(1, 1, 1);
            tsp.RenderAxes(1);

            % Cursor should work
            cursor = tsv.CursorMap(1);
            cap = EventCapture();
            lh = addlistener(cursor, 'CursorSnapped', @(~,e) cap.store(e));
            cursor.SetPosition(50);
            testCase.verifyNotEmpty(cap.Events, 'Cursor should work after clear+re-render');
            delete(lh);
        end
    end

    methods (Access = private)
        function expandDS(~, tsv)
            th = tsv.TableComp.GetTableHandle();
            th.CellSelectionCallback(th, struct('Indices', [1, 1]));
            pause(0.05);
        end
    end
end
