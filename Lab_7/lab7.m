%% Лабораторная работа № 7
% Коррекция перспективных искажений методом гомографии.
% MATLAB R2024a + Image Processing Toolbox.
% Запуск отчёта: make_report("lab7.m")
%
% Подобранные ниже координаты соответствуют V07.jpg размером 599x333,
% показанному в ранее сформированном lab7_report.pdf. Это приближённые
% точки на границе ПЛОСКОСТИ ФАСАДА, а не на отдельном окне.
% Если исходное изображение другое, необходимо указать его 4 угла вручную
% В КОДЕ (ginput не используется, чтобы отчёт создавался автоматически).

clc;
clear;
close all;

%% 1. Исходные данные и геометрия плоского объекта
imageFile = 'V07.jpg';

% Порядок: ЛВ -> ЛН -> ПН -> ПВ, координаты MATLAB [x,y].
% Область: фасад здания со всеми тремя окнами (внутри границ снимка).
% Координаты уточнены по изображению из ранее созданного PDF, поэтому
% при наличии оригинала их можно скорректировать на несколько пикселей.
movingPoints = [ 33  66; ... % левый верхний угол области фасада
                  0 322; ... % левый нижний
                594 317; ... % правый нижний
                534  42];    % правый верхний

if ~isfile(imageFile)
    error('lab7:FileNotFound', ...
        'Не найден файл %s. Поместите V07.jpg рядом с lab7.m.', imageFile);
end
img = imread(imageFile);
if ~(ismatrix(img) || (ndims(img) == 3 && size(img,3) == 3))
    error('lab7:InvalidImage', 'Допускается полутоновое или RGB-изображение.');
end
[imgHeight, imgWidth, ~] = size(img);

% Координаты заданы для конкретного варианта, а не для любого изображения.
if imgWidth ~= 599 || imgHeight ~= 333
    error('lab7:WrongVariant', ['Размер %s: %dx%d, а точки определены ' ...
        'для V07.jpg 599x333. Задайте movingPoints для своего снимка.'], ...
        imageFile, imgWidth, imgHeight);
end
if ~isequal(size(movingPoints), [4 2]) || any(~isfinite(movingPoints(:)))
    error('lab7:InvalidPoints', 'Необходимы четыре конечные пары [x,y].');
end
if any(movingPoints(:,1) < 1 | movingPoints(:,1) > imgWidth | ...
       movingPoints(:,2) < 1 | movingPoints(:,2) > imgHeight)
    error('lab7:OutOfBounds', 'Контрольные точки выходят за пределы снимка.');
end

% Проверка выпуклости и отсутствия самопересечений.
edgeVectors = diff([movingPoints; movingPoints(1,:)], 1, 1);
crossZ = edgeVectors(:,1).*edgeVectors([2 3 4 1],2) - ...
         edgeVectors(:,2).*edgeVectors([2 3 4 1],1);
if ~(all(crossZ > 0) || all(crossZ < 0))
    error('lab7:PointOrder', ...
        'Точки должны обходить один выпуклый четырёхугольник: ЛВ-ЛН-ПН-ПВ.');
end

% ВАЖНО: не растягиваем объект принудительно до 599x333.
% Размеры оцениваются по средним длинам противоположных сторон.
upperWidth  = norm(movingPoints(4,:) - movingPoints(1,:));
lowerWidth  = norm(movingPoints(3,:) - movingPoints(2,:));
leftHeight  = norm(movingPoints(2,:) - movingPoints(1,:));
rightHeight = norm(movingPoints(3,:) - movingPoints(4,:));
outWidth    = max(2, round((upperWidth + lowerWidth)/2));
outHeight   = max(2, round((leftHeight + rightHeight)/2));

% Физические размеры фасада неизвестны; пропорции — приближённые.
fixedPoints = [1        1; ...
               1        outHeight; ...
               outWidth outHeight; ...
               outWidth 1];

outDir = 'lab7_results';
if ~isfolder(outDir)
    mkdir(outDir);
end

fprintf('Лабораторная работа № 7 — коррекция перспективных искажений\n');
fprintf('Файл: %s; размер: %d x %d; класс: %s\n', ...
    imageFile, imgWidth, imgHeight, class(img));
fprintf('Объект: плоскость фасада со всеми тремя окнами.\n');
fprintf('Контрольные точки [x,y]:\n');
pointLabels = {'ЛВ','ЛН','ПН','ПВ'};
for k = 1:4
    fprintf('  %d (%s): (%7.2f, %7.2f) -> (%4d, %4d)\n', ...
        k, pointLabels{k}, movingPoints(k,1), movingPoints(k,2), ...
        fixedPoints(k,1), fixedPoints(k,2));
end
fprintf('Длины верх/низ: %.1f / %.1f пикс.; лево/право: %.1f / %.1f пикс.\n', ...
    upperWidth, lowerWidth, leftHeight, rightHeight);
fprintf('Расчётный размер результата: %d x %d пикселей.\n', ...
    outWidth, outHeight);
fprintf('Примечание: метрические размеры объекта не заданы, масштаб условен.\n');

%% 2. Исходная фотография
figure('Name','ЛР7 | Исходное изображение','Color','w', ...
    'Position',[80 80 1000 650]);
imshow(img, 'InitialMagnification','fit');
title('Рисунок 1. Исходный фасад с перспективными искажениями', ...
    'Interpreter','none');
imwrite(img, fullfile(outDir,'01_original.png'));

%% 3. Контрольные точки на единой плоскости фасада
figure('Name','ЛР7 | Углы фасада','Color','w', ...
    'Position',[100 100 1000 650]);
imshow(img, 'InitialMagnification','fit');
hold on;
outline = [movingPoints; movingPoints(1,:)];
plot(outline(:,1), outline(:,2), 'y-', 'LineWidth', 2.5);
plot(movingPoints(:,1), movingPoints(:,2), 'ro', ...
     'MarkerFaceColor','r','MarkerSize',9,'LineWidth',1.5);
for k = 1:4
    text(movingPoints(k,1) + 8, movingPoints(k,2), num2str(k), ...
        'Color','yellow','FontSize',13,'FontWeight','bold', ...
        'BackgroundColor',[0.1 0.1 0.1], 'Margin',2);
end
hold off;
title('Рисунок 2. Четыре угла плоскости фасада (ЛВ, ЛН, ПН, ПВ)', ...
    'Interpreter','none');
exportgraphics(gcf,fullfile(outDir,'02_control_points.png'), ...
    'Resolution',200);

%% 4. Гомография по четырём соответствиям
TFORM = fitgeotrans(movingPoints, fixedPoints, 'projective');

% MATLAB projective2d использует строчные векторы: [x y 1]*TFORM.T.
% H ниже рассчитана для столбцов: [x';y';1] ~ H*[x;y;1].
H = TFORM.T.';
if abs(H(3,3)) > 1e-12
    H = H/H(3,3);
end
if abs(det(H)) < 1e-12
    error('lab7:SingularHomography','Матрица гомографии вырождена.');
end
fprintf('\nМатрица H (столбцовая запись):\n');
disp(H);
fprintf('det(H) = %.9g\n',det(H));

%% 5. Исправленное изображение (без принудительного растяжения)
R = imref2d([outHeight outWidth]);
imgTransformed = imwarp(img, TFORM, 'linear', ...
    'OutputView',R, 'FillValues',0);

% Независимая бинарная маска покрытия выходного прямоугольника.
% nearest не интерполирует значения 0 и 1.
validMask = imwarp(true(imgHeight,imgWidth), TFORM, 'nearest', ...
    'OutputView',R);
validFraction = nnz(validMask)/numel(validMask);

figure('Name','ЛР7 | Результат коррекции','Color','w', ...
    'Position',[120 120 1000 650]);
imshow(imgTransformed, 'InitialMagnification','fit');
title(sprintf('Рисунок 3. Фасад после коррекции (%d x %d)', ...
    outWidth,outHeight), 'Interpreter','none');
imwrite(imgTransformed,fullfile(outDir,'03_corrected.png'));

%% 6. Сравнение исходного и исправленного фасада
figure('Name','ЛР7 | Сравнение','Color','w', ...
    'Position',[120 90 1280 620]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
nexttile;
imshow(img, 'InitialMagnification','fit');
hold on;
plot(outline(:,1),outline(:,2),'y-','LineWidth',2);
hold off;
title('До: исходный фасад и граница области');
nexttile;
imshow(imgTransformed,'InitialMagnification','fit');
title('После: выпрямленная плоскость фасада');
sgtitle('Рисунок 4. Сравнение геометрии до и после коррекции', ...
    'Interpreter','none');

%% 7. Маска валидных пикселей без дефекта экспорта однородного изображения
% Цветовая маска помогает видеть покрытие и не схлопывается до узкой полосы.
maskRGB = zeros(outHeight,outWidth,3,'uint8');
maskRGB(:,:,1) = uint8(~validMask)*220 + uint8(validMask)*45;
maskRGB(:,:,2) = uint8(~validMask)*55  + uint8(validMask)*185;
maskRGB(:,:,3) = uint8(~validMask)*55  + uint8(validMask)*90;
figure('Name','ЛР7 | Покрытие выходного кадра','Color','w', ...
    'Position',[140 100 1000 610]);
imshow(maskRGB,'InitialMagnification','fit');
axis on;
xlabel('X, пиксели');
ylabel('Y, пиксели');
title(sprintf(['Рисунок 5. Маска покрытия: зелёный — исходные данные, ' ...
    'красный — пустые области (%.2f%%)'],100*(1-validFraction)), ...
    'Interpreter','none');
imwrite(maskRGB,fullfile(outDir,'04_valid_mask_visualization.png'));
imwrite(validMask,fullfile(outDir,'05_valid_mask_binary.png'));

%% 8. Контрольная проверка математической точности
% У четырёх пар точек RMSE практически нулевой по построению; это НЕ
% независимая проверка геометрической правильности и резкости результата.
[xCheck,yCheck] = transformPointsForward(TFORM, ...
    movingPoints(:,1),movingPoints(:,2));
reprojected = [xCheck yCheck];
errors = sqrt(sum((reprojected-fixedPoints).^2,2));
rmsePoints = sqrt(mean(errors.^2));
maxPointError = max(errors);

fprintf('\nОшибки отображения четырёх опорных точек:\n');
for k = 1:4
    fprintf('  Точка %d: %.5e пикс.\n',k,errors(k));
end
fprintf('RMSE (только опорные точки) = %.5e пикс.\n',rmsePoints);
fprintf('Максимальная ошибка = %.5e пикс.\n',maxPointError);
fprintf('Покрытие выходного изображения = %.2f%%\n',100*validFraction);
fprintf('Незаполненные пиксели = %.2f%%\n',100*(1-validFraction));
fprintf('Отношение ширины к высоте после коррекции = %.4f\n', ...
    outWidth/outHeight);

% У projective2d нет единого глобального угла поворота и масштаба.
tformInv = invert(TFORM);
fprintf('\nОбратная матрица преобразования (форма MATLAB):\n');
disp(tformInv.T);
fprintf(['Scale и RotationAngle не являются свойствами общей projective2d; ' ...
    'исходные scaleFactor и theta для фотографии не предоставлены.\n']);

fprintf('\nЗАКЛЮЧЕНИЕ\n');
fprintf(['Выпрямлена одна плоскость фасада, охватывающая три окна. ' ...
    'Целевой размер получен из геометрии четырёхугольника.\n']);
fprintf(['Проверка: RMSE = %.3e пикс. по четырём использованным точкам; ' ...
    'покрытие = %.2f%%.\n'],rmsePoints,100*validFraction);
fprintf(['Практическое качество следует оценивать визуально: ' ...
    'прямолинейность рам, пропорции окон, отсутствие срезанных областей.\n']);
fprintf(['Без независимых геометрических ориентиров и эталона ' ...
    'метрическую точность подтвердить нельзя.\n']);
fprintf('Результаты: %s\n',fullfile(pwd,outDir));

% В конце НЕТ close all: открытые Figure забирает make_report.m.
