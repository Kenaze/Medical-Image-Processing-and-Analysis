function pdfPath = make_report(scriptFile, varargin)
%MAKE_REPORT Run a MATLAB script and build a generic PDF report.
%
%   pdfPath = make_report("script.m")
%
%   pdfPath = make_report("script.m", "Mode", "fit")
%   pdfPath = make_report("script.m", "Mode", "a4")
%
% The report contains:
%   1) console output produced by the script (disp, fprintf, whos, etc.);
%   2) every result figure that remains open after the script finishes.
%
% Each figure is placed in its own PDF page/section.
%
% MODE:
%   "fit" (default)
%       The PDF page size is calculated from the actual exported PNG size.
%       The page has zero margins and the image is scaled to fit the page.
%       Therefore, a landscape figure creates a landscape page and a
%       portrait figure creates a portrait page.
%
%   "a4"
%       Every figure is placed on its own A4 landscape page.
%
% The console section always uses A4 landscape pages.
%
% Backend: auto (default), dom, native. Native requires only MATLAB.
% Version 2.0. Target: R2026b Update 2 / MATLAB Online Basic.
% R2024b compatibility path uses print for console pages.
%
% Examples:
%   make_report("lab2.m");
%
%   make_report("lab2.m", ...
%       "Mode", "fit", ...
%       "OutputFile", "report.pdf");
%
%   make_report("lab2.m", ...
%       "Mode", "a4", ...
%       "OpenReport", false);
%
% Notes for scripts:
%   - clear / clc / close all at the beginning are allowed.
%   - Do not close result figures before the script ends.
%   - Create a separate figure for every result that must occupy a
%     separate page.
%   - Values that must appear in the report must be printed with disp,
%     fprintf, whos, etc.

    %% -------------------- Parse input --------------------
    p = inputParser;

    addRequired(p, "scriptFile", ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));

    addParameter(p, "OutputFile", "", ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));

    addParameter(p, "Mode", "fit", ...
        @(x) (ischar(x) || (isstring(x) && isscalar(x))) && ...
        any(strcmpi(string(x), ["fit", "a4"])));

    addParameter(p, "FigureDPI", 150, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);

    addParameter(p, "OpenReport", true, ...
        @(x) islogical(x) && isscalar(x));

    addParameter(p, "CloseBeforeRun", true, ...
        @(x) islogical(x) && isscalar(x));

    addParameter(p, "CloseAfterExport", true, ...
        @(x) islogical(x) && isscalar(x));

    addParameter(p, "IncludeConsole", true, ...
        @(x) islogical(x) && isscalar(x));

    addParameter(p, "IncludeHiddenFigures", false, ...
        @(x) islogical(x) && isscalar(x));

    addParameter(p, "Backend", "auto", ...
        @(x) (ischar(x) || (isstring(x) && isscalar(x))) && ...
        any(strcmpi(string(x), ["auto", "dom", "native"])));

    parse(p, scriptFile, varargin{:});
    opt = p.Results;

    scriptFile = string(opt.scriptFile);
    mode = lower(string(opt.Mode));
    figureDPI = double(opt.FigureDPI);

    %% -------------------- Select backend before running script --------------------
    backend = lower(string(opt.Backend));
    if backend ~= "native"
        [available, reason] = domAvailable();
        if ~available
            if backend == "dom"
                error("make_report:NoReportGenerator", "%s", reason);
            end
            fprintf("Report Generator unavailable: %s\nUsing native backend.\n", reason);
            backend = "native";
        end
    end

    if ~isfile(scriptFile)
        error("make_report:ScriptNotFound", ...
            "Script file not found: %s", scriptFile);
    end

    % Resolve an absolute path.
    [ok, attr] = fileattrib(char(scriptFile));
    if ~ok
        error("make_report:PathError", ...
            "Cannot resolve script path: %s", scriptFile);
    end
    scriptPath = string(attr.Name);

    [scriptDir, scriptName, scriptExt] = fileparts(scriptPath);

    if ~strcmpi(scriptExt, ".m")
        error("make_report:NotMScript", ...
            "Expected a .m script. Received: %s", scriptPath);
    end

    %% -------------------- Output path --------------------
    outputFile = string(opt.OutputFile);

    if strlength(outputFile) == 0
        outputFile = fullfile(scriptDir, scriptName + "_report.pdf");
    elseif ~isabsolute(outputFile)
        outputFile = fullfile(pwd, outputFile);
    end

    [outDir, outName, outExt] = fileparts(outputFile);

    if strlength(outDir) == 0
        outDir = pwd;
    end

    if strlength(outExt) == 0
        outputFile = fullfile(outDir, outName + ".pdf");
    elseif ~strcmpi(outExt, ".pdf")
        error("make_report:WrongOutputExtension", ...
            "OutputFile must have the .pdf extension.");
    end

    if ~isfolder(outDir)
        mkdir(outDir);
    end


    %% -------------------- Temporary folder --------------------
    tmpDir = string(tempname);
    mkdir(tmpDir);
    tmpCleanup = onCleanup(@() safeRemoveFolder(tmpDir)); %#ok<NASGU>

    %% -------------------- Prepare MATLAB session --------------------
    if opt.CloseBeforeRun
        try
            close all force;
        catch
            close all;
        end
    end

    drawnow;

    %% -------------------- Run script and capture console --------------------
    consoleText = runAndCapture(scriptPath);

    drawnow;

    %% -------------------- Collect figures --------------------
    figs = findall(groot, "Type", "figure");

    if ~opt.IncludeHiddenFigures && ~isempty(figs)
        keep = false(size(figs));
        for k = 1:numel(figs)
            try
                keep(k) = strcmpi(string(figs(k).Visible), "on");
            catch
                keep(k) = true;
            end
        end
        figs = figs(keep);
    end

    figs = sortFigures(figs);

    %% -------------------- Export all figures to PNG --------------------
    imageFiles = strings(numel(figs), 1);

    for k = 1:numel(figs)
        imageFiles(k) = fullfile(tmpDir, ...
            sprintf("figure_%04d.png", k));

        exportFigureSafe(figs(k), imageFiles(k), figureDPI);
    end

    %% -------------------- Create PDF in temporary folder --------------------
    % Never append to an old report or rerun the laboratory on fallback.
    staged = fullfile(tmpDir, "report.pdf");
    if backend == "native"
        createNativePDF(staged, imageFiles, consoleText, scriptName + scriptExt, opt, tmpDir);
    else
        try
            staged = createDomPDF(fullfile(tmpDir, "report"), imageFiles, ...
                consoleText, scriptName, scriptExt, mode, figureDPI, opt);
            backend = "dom";
        catch ME
            if lower(string(opt.Backend)) == "dom"
                rethrow(ME);
            end
            warning("make_report:DomFallback", "DOM failed: %s. Using native.", ME.message);
            backend = "native";
            staged = fullfile(tmpDir, "native_report.pdf");
            createNativePDF(staged, imageFiles, consoleText, scriptName + scriptExt, opt, tmpDir);
        end
    end
    [ok, msg] = movefile(char(staged), char(outputFile), 'f');
    if ~ok
        error("make_report:MoveFailed", "%s", msg);
    end
    pdfPath = string(outputFile);
    fprintf("PDF backend: %s\n", backend);

    %% -------------------- Cleanup figures --------------------
    if opt.CloseAfterExport
        for k = 1:numel(figs)
            try
                if isvalid(figs(k))
                    close(figs(k));
                end
            catch
            end
        end
    end

    %% -------------------- Result --------------------
    fprintf("\nPDF report created:\n%s\n", pdfPath);

    if opt.OpenReport
        try
            if backend == "dom"
                rptview(char(pdfPath));
            else
                web(char(pdfPath), '-browser');
            end
        catch ME
            warning("make_report:OpenFailed", ...
                "PDF saved. Open it manually: %s", ME.message);
        end
    end
end


%% ========================================================================
function consoleText = runAndCapture(scriptPath)
% Run the user's script in the BASE workspace.
%
% This is intentional: if the user script contains CLEAR, it clears the
% base workspace instead of destroying local variables of make_report().

    escapedPath = strrep(char(scriptPath), "'", "''");

    % Build the command as one STRING SCALAR.
    % This avoids sprintf([...]) receiving a string array in R2024b.
    wrappedCommand = ...
        "try" + newline + ...
        "    run('" + string(escapedPath) + "');" + newline + ...
        "catch ME" + newline + ...
        "    fprintf(2, '\n===== MATLAB ERROR =====\n%s\n', " + ...
        "getReport(ME, 'extended', 'hyperlinks', 'off'));" + newline + ...
        "end";

    % evalc captures Command Window output produced by evalin/run.
    consoleText = evalc("evalin('base', wrappedCommand);");
end


%% ========================================================================
function figs = sortFigures(figs)
% Sort standard figures by figure number where possible.
% If Number is unavailable, reverse FINDALL order as a reasonable
% approximation of creation order.

    if isempty(figs)
        return;
    end

    try
        nums = zeros(numel(figs), 1);
        for k = 1:numel(figs)
            nums(k) = double(figs(k).Number);
        end

        [~, order] = sort(nums);
        figs = figs(order);

    catch
        figs = flipud(figs);
    end
end


%% ========================================================================
function exportFigureSafe(figHandle, pngPath, dpi)
% Export a figure. EXPORTGRAPHICS is preferred; PRINT is a fallback.

    drawnow;

    try
        exportgraphics(figHandle, char(pngPath), ...
            "Resolution", dpi, ...
            "BackgroundColor", "white");
    catch
        resolutionArg = sprintf("-r%d", round(dpi));
        print(figHandle, char(pngPath), "-dpng", resolutionArg);
    end
end


%% ========================================================================
function layout = createA4LandscapeLayout(margin)
% Create a fixed A4 landscape PDF layout.

    import mlreportgen.dom.*;

    layout = PDFPageLayout();

    layout.PageSize.Height = "210mm";
    layout.PageSize.Width = "297mm";
    layout.PageSize.Orientation = "landscape";

    layout.PageMargins.Top = margin;
    layout.PageMargins.Bottom = margin;
    layout.PageMargins.Left = margin;
    layout.PageMargins.Right = margin;

    layout.PageMargins.Header = "0mm";
    layout.PageMargins.Footer = "0mm";
    layout.PageMargins.Gutter = "0mm";

    layout.SectionBreak = "Next Page";
end


%% ========================================================================
function layout = createFitLayout(pngPath, dpi)
% Create a PDF page whose physical dimensions correspond to the actual
% exported PNG dimensions at the specified DPI.
%
% Example:
%   1500 x 900 px at 150 dpi -> 10 x 6 inch PDF page.

    import mlreportgen.dom.*;

    info = imfinfo(char(pngPath));

    widthIn = double(info.Width) / dpi;
    heightIn = double(info.Height) / dpi;

    layout = PDFPageLayout();

    layout.PageSize.Width = sprintf("%.6fin", widthIn);
    layout.PageSize.Height = sprintf("%.6fin", heightIn);

    if widthIn >= heightIn
        layout.PageSize.Orientation = "landscape";
    else
        layout.PageSize.Orientation = "portrait";
    end

    % FIT means page bounds follow the image bounds.
    layout.PageMargins.Top = "0in";
    layout.PageMargins.Bottom = "0in";
    layout.PageMargins.Left = "0in";
    layout.PageMargins.Right = "0in";

    layout.PageMargins.Header = "0in";
    layout.PageMargins.Footer = "0in";
    layout.PageMargins.Gutter = "0in";

    layout.SectionBreak = "Next Page";
end


%% ========================================================================
function tf = isabsolute(pathText)
% Cross-platform absolute-path test.

    pathText = char(string(pathText));

    if ispc
        tf = ~isempty(regexp(pathText, ...
            '^[A-Za-z]:[\\/]|^\\\\', 'once'));
    else
        tf = startsWith(pathText, "/");
    end
end


%% ========================================================================
function safeRemoveFolder(folderPath)
% Best-effort removal of temporary files.

    try
        if isfolder(folderPath)
            rmdir(folderPath, "s");
        end
    catch
    end
end

function pdfPath = createDomPDF(outputBase, imageFiles, consoleText, scriptName, scriptExt, mode, figureDPI, opt)
    import mlreportgen.dom.*;

    doc = Document(char(outputBase), "pdf");
    try
        open(doc);
        % ---- Console section: always A4 landscape ----
        if opt.IncludeConsole
            consoleLayout = createA4LandscapeLayout("8mm");
            append(doc, consoleLayout);

            heading = Heading(1, "MATLAB: результаты выполнения");
            append(doc, heading);

            meta = Paragraph();
            append(meta, Text("Скрипт: " + scriptName + scriptExt));
            append(doc, meta);

            if strlength(string(consoleText)) == 0
                consoleText = "(Консольный вывод отсутствует)";
            end

            consoleBlock = Preformatted(consoleText);
            consoleBlock.FontSize = "7pt";
            consoleBlock.WhiteSpace = "pre-wrap";
            append(doc, consoleBlock);
        end

        % ---- One figure = one PDF page ----
        for k = 1:numel(imageFiles)
            pngPath = imageFiles(k);

            switch mode
                case "fit"
                    pageLayout = createFitLayout(pngPath, figureDPI);

                case "a4"
                    pageLayout = createA4LandscapeLayout("5mm");
            end

            % Appending a new PDFPageLayout starts a new layout section.
            append(doc, pageLayout);

            img = Image(char(pngPath));
            img.Style = {ScaleToFit(true)};
            append(doc, img);
        end

        % If both console and figures are absent, still generate a useful PDF.
        if ~opt.IncludeConsole && isempty(imageFiles)
            emptyLayout = createA4LandscapeLayout("8mm");
            append(doc, emptyLayout);
            append(doc, Paragraph("Нет данных для отчёта."));
        end

        close(doc);

    catch ME
        try
            close(doc);
        catch
        end
        rethrow(ME);
    end

    pdfPath = string(doc.OutputPath);

end

function [ok, reason] = domAvailable()
    ok = false;
    reason = "MATLAB Report Generator constructor not found.";
    if isempty(which("mlreportgen.dom.Document")), return; end
    try
        [status, msg] = license('checkout', 'MATLAB_Report_Gen');
        ok = logical(status);
        reason = string(msg);
    catch ME
        reason = string(ME.message);
    end
end

function createNativePDF(path, imageFiles, consoleText, scriptName, opt, tmpDir)
% Raster PDF with exact MediaBox; no Java, DOM, Python or external tools.
    a4 = [297 210] * 72 / 25.4;
    pages = strings(0,1);
    sizes = zeros(0,2);
    margins = zeros(0,1);
    if opt.IncludeConsole || isempty(imageFiles)
        if ~opt.IncludeConsole
            consoleText = 'Нет данных для отчёта.';
        elseif isempty(strtrim(consoleText))
            consoleText = '(Консольный вывод отсутствует)';
        end
        pages = renderConsole(consoleText, scriptName, tmpDir, opt.FigureDPI);
        sizes = repmat(a4, numel(pages), 1);
        margins = zeros(numel(pages),1); % margins already in rendered page
    end
    for k = 1:numel(imageFiles)
        pages(end+1,1) = imageFiles(k); %#ok<AGROW>
        info = imfinfo(char(imageFiles(k)));
        if strcmpi(opt.Mode, 'fit')
            sizes(end+1,:) = [info.Width info.Height] * 72 / opt.FigureDPI; %#ok<AGROW>
            margins(end+1,1) = 0; %#ok<AGROW>
        else
            sizes(end+1,:) = a4; %#ok<AGROW>
            margins(end+1,1) = 5 * 72 / 25.4; %#ok<AGROW>
        end
    end
    writeRasterPDF(path, pages, sizes, margins);
end

function files = renderConsole(consoleText, scriptName, tmpDir, dpi)
% Use MATLAB text renderer for Unicode, including Cyrillic. Wrap and paginate.
    txt = char(consoleText);
    txt = strrep(txt, sprintf('\r\n'), sprintf('\n'));
    txt = strrep(txt, sprintf('\r'), sprintf('\n'));
    txt = strrep(txt, sprintf('\t'), '    ');
    txt = regexprep(txt, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '');
    lines = regexp(txt, '\n', 'split');
    w = 297/25.4; h = 210/25.4;
    f = figure('Visible','off','Color','white','Units','inches', ...
        'Position',[0.1 0.1 w h], 'MenuBar','none','ToolBar','none', ...
        'InvertHardcopy','off');
    cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
    ax = axes('Parent',f,'Units','normalized','Position',[0 0 1 1], ...
        'XLim',[0 1],'YLim',[0 1],'Visible','off','Color','white');
    try
        fonts = string(listfonts);
    catch
        fonts = strings(0,1);
    end
    font = 'Courier New';
    candidates = ["DejaVu Sans Mono", "Liberation Mono", "Consolas", "Courier New", "Monospaced"];
    for name = candidates
        if any(strcmpi(fonts,name)), font = char(name); break; end
    end
    probe = text(ax,0,0,repmat('W',1,100),'Units','normalized', ...
        'Interpreter','none','FontName',font,'FontSize',8,'Color','black');
    drawnow;
    extent = probe.Extent;
    if isfinite(extent(3)) && extent(3)>0
        cols = max(1,min(160,floor(100*0.90/extent(3))));
    else
        cols = 120;
    end
    delete(probe);
    wrapped = cell(0,1);
    for k = 1:numel(lines)
        line = lines{k};
        if isempty(line), wrapped{end+1,1} = ''; end %#ok<AGROW>
        for j = 1:cols:length(line)
            wrapped{end+1,1} = line(j:min(j+cols-1,end)); %#ok<AGROW>
        end
    end
    perPage = 43;
    n = max(1,ceil(numel(wrapped)/perPage));
    files = strings(n,1);
    for k = 1:n
        delete(allchild(ax));
        text(ax,0.035,0.955,'MATLAB: результаты выполнения', ...
            'Interpreter','none','FontSize',13,'FontWeight','bold', ...
            'Color','black','VerticalAlignment','top');
        header = char(string(scriptName) + " | " + string(k) + "/" + string(n));
        text(ax,0.035,0.91,header,'Interpreter','none','FontSize',9, ...
            'Color','black','VerticalAlignment','top');
        first = (k-1)*perPage+1;
        last = min(k*perPage,numel(wrapped));
        for j = first:last
            text(ax,0.035,0.865-(j-first)*0.019,wrapped{j}, ...
                'Interpreter','none','FontName',font,'FontSize',8, ...
                'Color','black','VerticalAlignment','top');
        end
        drawnow;
        files(k) = fullfile(tmpDir,sprintf('console_%04d.png',k));
        % print preserves the full paper canvas on releases before R2025a.
        if ~verLessThan('matlab','25.1')
            try
                exportgraphics(f,char(files(k)),'Units','inches', ...
                    'Width',w,'Height',h,'Padding','figure', ...
                    'Resolution',dpi,'BackgroundColor','white');
                continue;
            catch
            end
        end
        set(f,'PaperUnits','inches','PaperSize',[w h], ...
            'PaperPositionMode','manual','PaperPosition',[0 0 w h]);
        print(f,char(files(k)),'-dpng',sprintf('-r%d',round(dpi)));
    end
end

function writeRasterPDF(path, pages, sizes, margins)
% PDF 1.4: one image XObject and one content stream per page.
% PNG IDAT is embedded losslessly using PDF PNG predictors when possible.
    [fid,msg] = fopen(char(path),'wb');
    if fid < 0, error('make_report:PDFOpen','%s',msg); end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    n = numel(pages);
    offsets = zeros(2+3*n,1);
    fprintf(fid,'%%PDF-1.4\n');
    fwrite(fid,uint8([37 226 227 207 211 10]),'uint8');
    offsets(1) = ftell(fid);
    fprintf(fid,'1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');
    offsets(2) = ftell(fid);
    fprintf(fid,'2 0 obj\n<< /Type /Pages /Count %d /Kids [',n);
    fprintf(fid,'%d 0 R ',3:3:3*n);
    fprintf(fid,'] >>\nendobj\n');
    for k = 1:n
        id = 3+3*(k-1);
        [data, iw, ih, filter] = pdfImageData(pages(k));
        pw = sizes(k,1); ph = sizes(k,2); m = margins(k);
        scale = min((pw-2*m)/iw,(ph-2*m)/ih);
        dw = iw*scale; dh = ih*scale;
        x = (pw-dw)/2; y = (ph-dh)/2;
        offsets(id) = ftell(fid);
        fprintf(fid,['%d 0 obj\n<< /Type /Page /Parent 2 0 R ' ...
            '/MediaBox [0 0 %.8f %.8f] /Resources << /XObject << /Im0 %d 0 R >> >> ' ...
            '/Contents %d 0 R >>\nendobj\n'],id,pw,ph,id+1,id+2);
        offsets(id+1) = ftell(fid);
        fprintf(fid,['%d 0 obj\n<< /Type /XObject /Subtype /Image /Width %d /Height %d ' ...
            '/ColorSpace /DeviceRGB /BitsPerComponent 8 %s /Length %d >>\nstream\n'], ...
            id+1,iw,ih,filter,numel(data));
        count = fwrite(fid,data,'uint8');
        if count ~= numel(data), error('make_report:PDFWrite','Incomplete image stream.'); end
        fprintf(fid,'\nendstream\nendobj\n');
        cmd = sprintf('q\n%.8f 0 0 %.8f %.8f %.8f cm\n/Im0 Do\nQ\n',dw,dh,x,y);
        offsets(id+2) = ftell(fid);
        fprintf(fid,'%d 0 obj\n<< /Length %d >>\nstream\n%s\nendstream\nendobj\n', ...
            id+2,numel(cmd),cmd);
    end
    start = ftell(fid);
    fprintf(fid,'xref\n0 %d\n0000000000 65535 f \n',numel(offsets)+1);
    fprintf(fid,'%010.0f 00000 n \n',offsets);
    fprintf(fid,'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%.0f\n%%%%EOF\n', ...
        numel(offsets)+1,start);
    [msg,errnum] = ferror(fid);
    if errnum ~= 0, error('make_report:PDFWrite','%s',msg); end
end

function [data,w,h,filter] = pdfImageData(path)
    [rgb,map,alpha] = imread(char(path));
    if ~isempty(map)
        idx = double(rgb);
        if isinteger(rgb) || islogical(rgb), idx = idx+1; end
        rgb = reshape(uint8(round(255*map(idx(:),:))),[size(idx),3]);
    elseif isa(rgb,'uint16')
        rgb = uint8(round(double(rgb)/257));
    elseif islogical(rgb)
        rgb = uint8(rgb).*uint8(255);
    elseif ~isa(rgb,'uint8')
        rgb = uint8(round(255*min(max(double(rgb),0),1)));
    end
    if size(rgb,3)==1, rgb = repmat(rgb,1,1,3); end
    if ~isempty(alpha)
        if isinteger(alpha), a = double(alpha)/double(intmax(class(alpha)));
        else, a = double(alpha); end
        rgb = uint8(round(double(rgb).*a + 255*(1-a)));
    end
    [h,w,~] = size(rgb);
    % Re-encode RGB as PNG to remove palette/alpha and reuse its zlib stream.
    temp = string(tempname)+".png";
    cleaner = onCleanup(@() deleteIfExists(temp)); %#ok<NASGU>
    imwrite(rgb,char(temp),'png');
    [fid,msg] = fopen(char(temp),'rb');
    if fid<0, error('make_report:PNGOpen','%s',msg); end
    closer = onCleanup(@() fclose(fid));
    bytes = fread(fid,Inf,'*uint8');
    clear closer;
    data = uint8([]); filter = '';
    % IHDR: bit depth 8, RGB (2), no interlace.
    if numel(bytes)>=33 && isequal(bytes(25:29).',uint8([8 2 0 0 0]))
        pos = 9; chunks = {};
        while pos+11<=numel(bytes)
            len = sum(double(bytes(pos:pos+3)).'.*[16777216 65536 256 1]);
            if pos+11+len>numel(bytes), break; end
            tag = char(bytes(pos+4:pos+7).');
            if strcmp(tag,'IDAT'), chunks{end+1,1} = bytes(pos+8:pos+7+len); end %#ok<AGROW>
            if strcmp(tag,'IEND'), break; end
            pos = pos+12+len;
        end
        if ~isempty(chunks)
            data = vertcat(chunks{:});
            filter = sprintf('/Filter /FlateDecode /DecodeParms << /Predictor 15 /Colors 3 /BitsPerComponent 8 /Columns %d >>',w);
        end
    end
    if isempty(data)
        data = reshape(permute(rgb,[3 2 1]),[],1); % RGB, row-major
    end
end

function deleteIfExists(path)
    if isfile(path), delete(path); end
end
