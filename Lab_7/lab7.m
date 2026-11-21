%% Лабораторная работа № 7
% Коррекция перспективных искажений методом гомографии.
% MATLAB R2024a + Image Processing Toolbox.
% Скрипт предназначен для вызова make_report("lab7.m").
% ВАЖНО: укажите реальное изображение своего варианта и его 4 угла ниже.
% ginput не используется, так как make_report запускает скрипт без диалога.

clc;
clear;
close all;

%% 1. Входные данные и контрольные точки
imageFile = 'Book1.jpg'; % ЗАМЕНИТЬ на имя файла своего варианта

% ОБРАЗЕЦ из методички для Book1.jpg; для своего варианта ЗАМЕНИТЬ.
% Последовательность: ЛВ -> ЛН -> ПН -> ПВ, координаты [x, y].
movingPoints = [126 58; ...   % левый верхний
                 21 222; ...  % левый нижний
                 215 237; ... % правый нижний
                 205 59];     % правый верхний

if ~isfile(imageFile)
    error('lab7:FileNotFound', ['Не найден файл "%s". Поместите фотографию ' ...
        'своего варианта рядом с lab7.m и задайте imageFile.'], imageFile);
end

img = imread(imageFile);
if ~(ndims(img) == 2 || (ndims(img) == 3 && size(img, 3) == 3))
    error('lab7:InvalidImage', 'Требуется полутоновое или RGB-изображение.');
end

[imgHeight, imgWidth, ~] = size(img);
if ~isequal(size(movingPoints), [4 2]) || any(~isfinite(movingPoints(:)))
    error('lab7:InvalidPoints', 'movingPoints должны содержать четыре пары [x, y].');
end
if any(movingPoints(:,1) < 1 | movingPoints(:,1) > imgWidth | ...
       movingPoints(:,2) < 1 | movingPoints(:,2) > imgHeight)
    error('lab7:PointsOutOfBounds', ...
        'Углы выходят за границы снимка %d x %d. Укажите углы своего варианта.', ...
        imgWidth, imgHeight);
end

% Проверяем отсутствие вырожденной конфигурации (три коллинеарные точки).
for a = 1:2
    for b = a+1:3
        for c = b+1:4
            triangle = [movingPoints([a b c], :) ones(3,1)];
            if abs(det(triangle)) < 1e-7 * max(imgWidth, imgHeight)^2
                error('lab7:CollinearPoints', 'Три контрольные точки лежат на прямой.');
            end
        end
    end
end

% Все последовательные углы должны образовывать один выпуклый четырехугольник.
edges = diff([movingPoints; movingPoints(1,:)], 1, 1);
crossZ = edges(:,1).*edges([2 3 4 1],2) - ...
         edges(:,2).*edges([2 3 4 1],1);
if ~(all(crossZ > 0) || all(crossZ < 0))
    error('lab7:PointOrder', ...
        'Точки должны идти по контуру: ЛВ, ЛН, ПН, ПВ, без пересечений.');
end

outDir = 'lab7_results';
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

fprintf('Лабораторная работа № 7: коррекция перспективных искажений\n');
fprintf('Входной файл: %s\n', imageFile);
fprintf('Размер исходного изображения: %d x %d пикселей\n', imgWidth, imgHeight);
fprintf('Тип изображения: %s\n', class(img));
fprintf('\nКонтрольные точки [x, y], порядок ЛВ - ЛН - ПН - ПВ:\n');
disp(array2table(movingPoints, 'VariableNames', {'X', 'Y'}, ...
    'RowNames', {'ЛВ', 'ЛН', 'ПН', 'ПВ'}));

%% 2. Исходное изображение
figure('Name', 'ЛР7 - исходное изображение', 'Color', 'w');
imshow(img);
title('Рисунок 1. Исходное изображение с перспективными искажениями');
imwrite(img, fullfile(outDir, '01_original.png'));

%% 3. Контрольные точки на исходном изображении
figure('Name', 'ЛР7 - контрольные точки', 'Color', 'w');
imshow(img);
hold on;
plot([movingPoints(:,1); movingPoints(1,1)], ...
     [movingPoints(:,2); movingPoints(1,2)], ...
     'y-', 'LineWidth', 2);
plot(movingPoints(:,1), movingPoints(:,2), 'ro', ...
     'MarkerSize', 10, 'LineWidth', 2, 'MarkerFaceColor', 'r');
for k = 1:4
    text(movingPoints(k,1)+5, movingPoints(k,2)+5, num2str(k), ...
         'Color', 'yellow', 'FontSize', 12, 'FontWeight', 'bold');
end
hold off;
title('Рисунок 2. Контрольные точки: 1-ЛВ, 2-ЛН, 3-ПН, 4-ПВ');
exportgraphics(gcf, fullfile(outDir, '02_control_points.png'), 'Resolution', 200);

%% 4. Целевые точки и матрица гомографии
% В соответствии с методичкой объект выпрямляется на весь размер кадра.
% Начало системы пиксельных координат MATLAB: (1,1).
fixedPoints = [1        1; ...
               1        imgHeight; ...
               imgWidth imgHeight; ...
               imgWidth 1];

fprintf('\nЦелевые точки [x, y]:\n');
disp(array2table(fixedPoints, 'VariableNames', {'X', 'Y'}, ...
    'RowNames', {'ЛВ', 'ЛН', 'ПН', 'ПВ'}));

% Сохраняем fitgeotrans, прямо указанную в методическом задании.
TFORM = fitgeotrans(movingPoints, fixedPoints, 'projective');

% Объект projective2d хранит матрицу для умножения СТРОКИ [x y 1]*T.
% Для принятой в методичке записи СТОЛБЦА [x';y';1]~H*[x;y;1]:
H = TFORM.T.';
H = H ./ H(3,3);

fprintf('\nМатрица гомографии H (для векторов-столбцов):\n');
disp(H);
fprintf('Определитель H: %.9g\n', det(H));

%% 5. Преобразование изображения
% imref2d(sz) точно связывает центры пикселей с координатами 1..W и 1..H.
R = imref2d([imgHeight imgWidth]);
imgTransformed = imwarp(img, TFORM, 'linear', 'OutputView', R, ...
    'FillValues', 0);

% Независимая маска полезной части: ноль на недостающих пикселях.
validMask = imwarp(true(imgHeight, imgWidth), TFORM, 'nearest', ...
    'OutputView', R);

figure('Name', 'ЛР7 - исправленное изображение', 'Color', 'w');
imshow(imgTransformed);
title('Рисунок 3. Изображение после коррекции перспективы');
imwrite(imgTransformed, fullfile(outDir, '03_corrected.png'));

figure('Name', 'ЛР7 - сравнение', 'Color', 'w', ...
    'Position', [100 100 1100 520]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
imshow(img);
title('До коррекции');
nexttile;
imshow(imgTransformed);
title('После коррекции');
sgtitle('Рисунок 4. Сравнение исходного и исправленного изображения');

figure('Name', 'ЛР7 - маска валидных пикселей', 'Color', 'w');
imshow(validMask);
title('Рисунок 5. Маска пикселей, для которых известен исходный цвет');
imwrite(validMask, fullfile(outDir, '04_valid_mask.png'));

%% 6. Численная оценка качества
% Репроекционная ошибка измеряется именно в четырёх заданных точках.
[xCheck, yCheck] = transformPointsForward(TFORM, ...
    movingPoints(:,1), movingPoints(:,2));
reprojected = [xCheck yCheck];
pointErrors = vecnorm(reprojected - fixedPoints, 2, 2);
rmsePoints = sqrt(mean(pointErrors.^2));
maxPointError = max(pointErrors);
validFraction = nnz(validMask) / numel(validMask);

fprintf('\nОшибки отображения четырёх контрольных точек (пиксели):\n');
disp(table((1:4).', pointErrors, ...
    'VariableNames', {'PointNumber', 'ErrorPixels'}));
fprintf('RMSE по контрольным точкам: %.9f пикселя\n', rmsePoints);
fprintf('Максимальная ошибка: %.9f пикселя\n', maxPointError);
fprintf('Доля пикселей с известными данными в выходном кадре: %.2f %%\n', ...
    100*validFraction);
fprintf('Доля незаполненных пикселей: %.2f %%\n', ...
    100*(1-validFraction));

% Инверсная гомография: в общем случае не является поворотом + масштабом.
tformInv = invert(TFORM);
fprintf('\nОбратная матрица преобразования (строчная форма MATLAB):\n');
disp(tformInv.T);
fprintf(['Scale и RotationAngle не являются глобальными параметрами ' ...
    'общего projective2d.\n']);
fprintf(['Исходные scaleFactor и theta не заданы методичкой как ' ...
    'параметры этой фотографии.\n']);
fprintf(['Поэтому сравнение Scale/RotationAngle со scaleFactor/theta ' ...
    'для данной гомографии не проводится.\n']);

fprintf('\nЗАКЛЮЧЕНИЕ\n');
fprintf(['Четыре угла объекта сопоставлены с углами прямоугольника; ' ...
    'по ним вычислена гомография.\n']);
fprintf(['RMSE в контрольных точках = %.6g пикселя; ' ...
    'доля незаполненных пикселей = %.2f %%.\n'], ...
    rmsePoints, 100*(1-validFraction));
fprintf(['Малая ошибка в четырех опорных точках не доказывает ' ...
    'сохранность деталей и отсутствие ошибок вне этих точек.\n']);
fprintf(['Проверка геометрии объекта и качества интерполяции ' ...
    'дополнительно выполняется по рисункам 3-5.\n']);
fprintf('Результаты сохранены в папке: %s\n', fullfile(pwd,outDir));

%% 7. Переменные рабочей области
fprintf('\nПеременные MATLAB:\n');
whos

% В конце НЕ вызывать close all: make_report собирает открытые Figure.
