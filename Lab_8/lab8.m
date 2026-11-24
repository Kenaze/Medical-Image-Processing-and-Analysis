%% Лабораторная работа № 8. Нежёсткая регистрация изображений (Demons)
% MATLAB R2026b Update 2, Image Processing Toolbox.
% Запуск отчёта из Command Window: make_report("lab8.m");
% Поместите рядом с lab8.m два собственных снимка: fixed.jpg и moving.jpg.
% make_report.m должен быть в текущем каталоге или на MATLAB path.
clc;
clear;
close all;

%% 1. Настройки и исходные снимки
fixedFile = 'fixed.jpg';
movingFile = 'moving.jpg';
maxDimension = 1024;           % 0 = не уменьшать изображения
smoothValues = [0.5 1.3 3.0];
iterationSets = {[150 100 50], [500 400 200]};
outputDir = 'lab8_results';

if ~isfile(fixedFile) || ~isfile(movingFile)
    error('Lab8:MissingImages', ['Разместите fixed.jpg и moving.jpg рядом ' ...
        'со скриптом. Требуются две реальные фотографии одного объекта.']);
end
if ~isfolder(outputDir)
    mkdir(outputDir);
end

fixedRGB = imread(fixedFile);
movingRGB = imread(movingFile);
if size(fixedRGB,3) ~= 3 || size(movingRGB,3) ~= 3
    error('Lab8:RGBRequired', 'По практическому заданию нужны два цветных RGB-снимка.');
end
if ~isequal(size(fixedRGB),size(movingRGB))
    error('Lab8:SizeMismatch', ['Размеры снимков различаются. ' ...
        'Снимайте с одной позиции и заранее приведите изображения ' ...
        'к одинаковому размеру, не меняя геометрию объекта.']);
end
originalSize = size(fixedRGB);
if maxDimension > 0 && max(originalSize(1:2)) > maxDimension
    scale = maxDimension/max(originalSize(1:2));
    fixedRGB = imresize(fixedRGB,scale);
    movingRGB = imresize(movingRGB,scale);
end
fixed = im2single(im2gray(fixedRGB));
moving = im2single(im2gray(movingRGB));
movingMatched = imhistmatch(moving,fixed);

fprintf('Лабораторная работа № 8 — нежёсткая регистрация Demons\n');
fprintf('MATLAB: %s\n',version);
fprintf('Входные файлы: %s; %s\n',fixedFile,movingFile);
fprintf('Исходный размер: %d x %d пикселей\n',originalSize(2),originalSize(1));
fprintf('Рабочий размер: %d x %d пикселей\n',size(fixed,2),size(fixed,1));
fprintf('Число экспериментов: %d\n',numel(smoothValues)*numel(iterationSets));

%% 2. Исходные RGB-изображения и их несовпадение
figure('Name','01. Исходные фотографии','Color','w','Position',[100 100 1100 470]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
nexttile; imshow(fixedRGB); title('Опорное цветное изображение (fixed)');
nexttile; imshow(movingRGB); title('Деформированное цветное изображение (moving)');

figure('Name','02. Полутоновые изображения','Color','w','Position',[100 100 1100 470]);
imshowpair(fixed,moving,'montage');
title('Опорное изображение слева, деформируемое справа');

figure('Name','03. Исходное наложение','Color','w','Position',[100 100 850 650]);
imshowpair(fixed,moving);
title('До регистрации: зелёные и пурпурные области несовпадения');

figure('Name','04. Согласование гистограмм','Color','w','Position',[100 100 1050 430]);
tiledlayout(1,3,'Padding','compact','TileSpacing','compact');
nexttile; imhist(fixed); title('Гистограмма fixed');
nexttile; imhist(moving); title('Гистограмма moving');
nexttile; imhist(movingMatched); title('После imhistmatch');

%% 3. Контрольные метрики на одинаковой области и шкале [0,1]
% MSE -> минимум; NCC -> максимум. Не заменяют анатомическую оценку.
mseInitial = mean((fixed(:)-moving(:)).^2);
mseMatched = mean((fixed(:)-movingMatched(:)).^2);
nccInitial = corr2(fixed,moving);
nccMatched = corr2(fixed,movingMatched);
fprintf('\nДо регистрации: MSE = %.6f; NCC = %.6f\n',mseInitial,nccInitial);
fprintf('После imhistmatch, до геометрической регистрации: MSE = %.6f; NCC = %.6f\n', ...
    mseMatched,nccMatched);

%% 4. Эксперимент с числом итераций и сглаживанием
nTests = numel(smoothValues)*numel(iterationSets);
caseNumber = (1:nTests).';
sigmaOut = zeros(nTests,1);
iterationLabel = strings(nTests,1);
mseOut = zeros(nTests,1);
nccOut = zeros(nTests,1);
meanDisplacement = zeros(nTests,1);
maxDisplacement = zeros(nTests,1);
elapsedSeconds = zeros(nTests,1);
fields = cell(nTests,1);
registeredGrays = cell(nTests,1);

k = 0;
for s = 1:numel(smoothValues)
    for q = 1:numel(iterationSets)
        k = k + 1;
        sigma = smoothValues(s);
        iterations = iterationSets{q};
        fprintf('\nЭксперимент %d/%d: smoothing=%.1f, iterations=[%s]\n', ...
            k,nTests,sigma,num2str(iterations));
        tStart = tic;
        [D,reg] = imregdemons(movingMatched,fixed,iterations, ...
            'AccumulatedFieldSmoothing',sigma,'DisplayWaitbar',false);
        elapsedSeconds(k) = toc(tStart);
        fieldMagnitude = hypot(D(:,:,1),D(:,:,2));
        sigmaOut(k) = sigma;
        iterationLabel(k) = strtrim(sprintf('%d ',iterations));
        mseOut(k) = mean((fixed(:)-reg(:)).^2);
        nccOut(k) = corr2(fixed,reg);
        meanDisplacement(k) = mean(fieldMagnitude(:));
        maxDisplacement(k) = max(fieldMagnitude(:));
        fields{k} = D;
        registeredGrays{k} = reg;
        fprintf('  MSE=%.6f; NCC=%.6f; mean|D|=%.3f px; max|D|=%.3f px; %.1f s\n', ...
            mseOut(k),nccOut(k),meanDisplacement(k),maxDisplacement(k),elapsedSeconds(k));
    end
end

T = table(caseNumber,sigmaOut,iterationLabel,mseOut,nccOut, ...
    meanDisplacement,maxDisplacement,elapsedSeconds, ...
    'VariableNames',{'Case','Smoothing','Iterations','MSE','NCC', ...
    'MeanDisp_px','MaxDisp_px','Time_s'});
disp(' ');
disp('Сводная таблица экспериментов:');
disp(T);
writetable(T,fullfile(outputDir,'registration_metrics.csv'));

% Автоматический выбор по минимальной MSE при фиксированной шкале яркости.
% Этот критерий не гарантирует отсутствия нереалистичных деформаций.
[~,bestIdx] = min(mseOut);
D = fields{bestIdx};
movingReg = registeredGrays{bestIdx};
mag = hypot(D(:,:,1),D(:,:,2));
fprintf('\nВыбран эксперимент %d: smoothing=%.1f; iterations=[%s]\n', ...
    bestIdx,sigmaOut(bestIdx),char(iterationLabel(bestIdx)));
fprintf('MSE: %.6f -> %.6f (относительное изменение %.2f%%)\n', ...
    mseMatched,mseOut(bestIdx),100*(mseMatched-mseOut(bestIdx))/max(mseMatched,eps));
fprintf('NCC: %.6f -> %.6f\n',nccMatched,nccOut(bestIdx));
fprintf('Важно: статистика не гарантирует визуально или анатомически корректного совмещения.\n');

%% 5. Цветное преобразование тем же полем смещения
movingRegRGB = imwarp(movingRGB,D,'linear');
if ~isequal(size(movingRegRGB),size(fixedRGB))
    error('Lab8:WarpSize','Результат imwarp не совпадает по размеру с опорным кадром.');
end

figure('Name','05. Результат: наложение','Color','w','Position',[100 100 950 650]);
imshowpair(fixed,movingReg);
title(sprintf('Demons: наложение после регистрации (\sigma = %.1f)',sigmaOut(bestIdx)));

figure('Name','06. Результат: рядом','Color','w','Position',[100 100 1100 470]);
imshowpair(fixed,movingReg,'montage');
title('Опорное слева и зарегистрированное справа');

figure('Name','07. Зарегистрированное цветное изображение','Color','w', ...
    'Position',[100 100 1100 470]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
nexttile; imshow(fixedRGB); title('Опорное RGB');
nexttile; imshow(movingRegRGB); title('Зарегистрированное RGB (imwarp)');

%% 6. Визуализация поля смещений D
figure('Name','08. Модуль поля смещений','Color','w','Position',[100 100 850 640]);
imagesc(mag); axis image ij; colormap(gca,'turbo'); colorbar;
title('Модуль поля смещений |D|, пиксели');
xlabel('X, пиксели'); ylabel('Y, пиксели');

figure('Name','09. Векторы поля смещений','Color','w','Position',[100 100 850 640]);
imshow(fixed,[]); hold on;
step = max(8,round(min(size(fixed))/25));
[X,Y] = meshgrid(1:step:size(fixed,2),1:step:size(fixed,1));
U = D(1:step:end,1:step:end,1);
V = D(1:step:end,1:step:end,2);
quiver(X,Y,U,V,1.5,'Color',[1 0.8 0.1],'LineWidth',1);
hold off;
title('Поле деформации D: направление и величина смещений');

%% 7. Сравнение параметров алгоритма
figure('Name','10. Сравнение метрик экспериментов','Color','w', ...
    'Position',[100 100 1100 480]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
nexttile;
bar(caseNumber,mseOut); hold on; yline(mseMatched,'--','До Demons'); hold off;
title('MSE: меньше — лучше'); xlabel('Номер эксперимента'); ylabel('MSE');
xticks(caseNumber);
nexttile;
bar(caseNumber,nccOut); hold on; yline(nccMatched,'--','До Demons'); hold off;
title('NCC: больше — лучше'); xlabel('Номер эксперимента'); ylabel('NCC');
xticks(caseNumber);

%% 8. Сохранение результатов (независимо от PDF-отчёта)
imwrite(fixedRGB,fullfile(outputDir,'fixed_used.png'));
imwrite(movingRGB,fullfile(outputDir,'moving_used.png'));
imwrite(movingRegRGB,fullfile(outputDir,'moving_registered_rgb.png'));
imwrite(movingReg,fullfile(outputDir,'moving_registered_gray.png'));
save(fullfile(outputDir,'displacement_field.mat'),'D','T','bestIdx', ...
    'smoothValues','iterationSets');
fprintf('\nФайлы результатов сохранены в папке: %s\n',fullfile(pwd,outputDir));
fprintf(['Вывод: для объективного сравнения учитывайте MSE, NCC, ' ...
    'величину смещений и отсутствие визуальных складок/разрывов.\n']);
fprintf(['Слабое сглаживание допускает более локальные деформации, ' ...
    'сильное — делает поле более гладким, но может недосовместить детали.\n']);
fprintf('Перед выводами проверьте рисунки 05–09: автоматический минимум MSE не всегда идеален.\n');

% ВАЖНО: не закрывать Figure — make_report.m сам соберёт их в PDF.
