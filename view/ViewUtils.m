classdef ViewUtils
% ViewUtils - 视图层公共工具（静态方法集合）
%
% legend 管理、Loading 弹窗、错误提示、文件选择对话框等共用 UI 工具。

    methods (Static)
        function CleanupBrokenLegends(fig)
        % CleanupBrokenLegends 删除空条目 legend（隐藏页签内创建产生的工件）
            legs = findobj(fig, 'Type', 'legend');
            for i = 1:numel(legs)
                if isempty(legs(i).PlotChildren)
                    delete(legs(i));
                end
            end
        end

        function RefreshLegendFor(ax, fig)
        % RefreshLegendFor 为指定 uiaxes 重建 legend（若无 legend 且 ≥2 条线）
            legs = findobj(fig, 'Type', 'legend');
            hasLegend = false;
            for i = 1:numel(legs)
                kids = legs(i).PlotChildren;
                if ~isempty(kids) && any(arrayfun(@(k) isequal(ancestor(k, 'axes'), ax), kids))
                    hasLegend = true;
                end
            end
            if hasLegend, return; end
            lines = findobj(ax, 'Type', 'line');
            if numel(lines) >= 2
                legend(ax, 'Interpreter', 'none', 'Location', 'northwest');
            end
        end

        function ShowError(parent, msg)
        % ShowError 显示错误提示弹窗
            fig = ancestor(parent, 'figure');
            if isempty(fig), fig = parent; end
            uialert(fig, msg, '错误', 'Icon', 'error');
        end

        function folderPath = SelectFolder(startPath)
        % SelectFolder 弹出文件夹选择对话框
            folderPath = uigetdir(startPath, 'Select Folder');
            if isequal(folderPath, 0)
                folderPath = '';
            end
        end

        function [fileNames, filePaths] = SelectFiles(startPath, filterSpec)
        % SelectFiles 弹出多文件选择对话框
            if nargin < 2 || isempty(filterSpec)
                filterSpec = {'*.*', 'All Files (*.*)'};
            end
            [fileNames, pathName] = uigetfile(filterSpec, 'Select Files', startPath, 'MultiSelect', 'on');
            if isequal(fileNames, 0)
                fileNames = {};
                filePaths = {};
            elseif ischar(fileNames)
                fileNames = {fileNames};
                filePaths = {fullfile(pathName, fileNames{1})};
            else
                filePaths = cellfun(@(f) fullfile(pathName, f), fileNames, 'UniformOutput', false);
            end
        end

        function DeleteDataLines(ax)
        % DeleteDataLines 删除 axes 上的数据线，保留游标对象。
        %   替代 cla(ax)，避免误杀游标的 xline/line/text 图形。
        %   NEVER delete 'constantline' — cursor's XLineH (xline) may not
        %   be discoverable by findobj in all MATLAB versions.
            allChildren = findobj(ax);
            for i = 1:numel(allChildren)
                ch = allChildren(i);
                if ch == ax, continue; end
                if isprop(ch, 'Tag') && strcmp(ch.Tag, 'cursor')
                    continue
                end
                t = get(ch, 'Type');
                if strcmp(t, 'line') || strcmp(t, 'text')
                    delete(ch);
                end
            end
        end
    end
end
