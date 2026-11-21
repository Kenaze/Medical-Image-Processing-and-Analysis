%% Лабораторная работа № 6
% Регистрация изображений: нахождение поворота и масштаба.
% MATLAB R2024a; Image Processing Toolbox + Computer Vision Toolbox.
% Скрипт предназначен для запуска через make_report('lab6.m').
clc;
clear;
close all;

%% 1. Вариант и исходные данные
variantNumber = 3;  % <-- Замените на свой вариант (1...12)
imageFile = 'cameraman.tif'; % <-- Замените на файл вашего варианта

variantScale = [0.5 0.6 0.7 0.8 0.9 0.5 0.6 0.7 0.8 0.9 0.4 0.3];
variantAngle = [15 20 30 45 60 25 35 40 50 55 45 65];
assert(isscalar(variantNumber) && variantNumber == fix(variantNumber) && ...
    variantNumber >= 1 && variantNumber <= 12, ...
    'Номер варианта должен быть целым от 1 до 12.');
scaleFactor = variantScale(variantNumber);
theta = variantAngle(variantNumber);

assert(exist(imageFile,'file') == 2, ...
    'Изображение %s не найдено. Поместите его рядом со скриптом.', imageFile);
original = imread(imageFile);
if ndims(original) == 3
    original = rgb2gray(original);
end
if ~isa(original,'uint8')
    original = im2uint8(mat2gray(original));
end

fprintf('Лабораторная работа № 6. Регистрация изображений.\n');
fprintf('MATLAB R2024a; вариант %d.\n', variantNumber);
fprintf('Файл: %s; размер: %d x %d пикселей.\n', ...
    imageFile, size(original,2), size(original,1));
fprintf('Заданные параметры: scaleFactor = %.4f, theta = +%.2f град.\n', ...
    scaleFactor, theta);
fprintf('Примечание: +theta для imrotate — против часовой стрелки.\n\n');

figure('Name','01 - Исходное изображение','Color','w');
imshow(original);
title(sprintf('Исходное полутоновое изображение — вариант %d', variantNumber));

%% 2. Искажение по параметрам варианта
scaled = imresize(original,scaleFactor);
distorted = imrotate(scaled,theta,'bilinear','loose');
figure('Name','02 - Искаженное изображение','Color','w');
imshow(distorted);
title(sprintf('Масштаб %.2f; поворот +%.0f° (imrotate)',scaleFactor,theta));
fprintf('Размер после искажения: %d x %d пикселей.\n\n', ...
    size(distorted,2),size(distorted,1));

%% 3. Автоматический поиск и проверка пар соответствующих точек
% В отличие от интерактивного cpselect этот способ не останавливает
% автоматический запуск универсального генератора отчётов.
% При этом соответствия ищутся на ИЗОБРАЖЕНИЯХ, а не вычисляются
% заранее по известным scaleFactor и theta.
pointsMoving = detectSIFTFeatures(distorted,'ContrastThreshold',0.005);
pointsFixed  = detectSIFTFeatures(original,'ContrastThreshold',0.005);
[featuresMoving, validMoving] = extractFeatures(distorted,pointsMoving);
[featuresFixed,  validFixed]  = extractFeatures(original,pointsFixed);
pairs = matchFeatures(featuresMoving,featuresFixed, ...
    'Unique',true,'MaxRatio',0.85,'MatchThreshold',80);

if size(pairs,1) < 10
    error(['Найдено только %d сопоставлений (нужно >= 10). ' ...
        'Попробуйте более текстурированное изображение.'],size(pairs,1));
end
movingMatched = validMoving(pairs(:,1)).Location;
fixedMatched  = validFixed(pairs(:,2)).Location;

% MSAC/RANSAC удаляет ложные соответствия до вызова fitgeotform2d.
[~, inlierIndex] = estgeotform2d(movingMatched,fixedMatched, ...
    'similarity','MaxDistance',3,'MaxNumTrials',5000,'Confidence',99.9);
movingInliers = movingMatched(inlierIndex,:);
fixedInliers  = fixedMatched(inlierIndex,:);
if size(movingInliers,1) < 10
    error(['После исключения ложных соответствий осталось %d пар (нужно >= 10). ' ...
        'Выберите другой снимок с различимыми деталями.'],size(movingInliers,1));
end

% Равномерное покрытие изображения: выбираем наиболее удалённые пары.
% Первые 5 точек входят в набор из 10, поэтому сравнение корректно.
numPairsSmall = 5;
numPairsLarge = 10;
xy = fixedInliers;
selected = zeros(numPairsLarge,1);
center = mean(xy,1);
[~,selected(1)] = min(sum((xy-center).^2,2));
minDistSq = inf(size(xy,1),1);
for k = 2:numPairsLarge
    prev = xy(selected(k-1),:);
    minDistSq = min(minDistSq,sum((xy-prev).^2,2));
    minDistSq(selected(1:k-1)) = -Inf;
    [~,selected(k)] = max(minDistSq);
end

fprintf('Всего совпадений SIFT: %d; геометрически согласованных: %d.\n', ...
    size(pairs,1),size(movingInliers,1));
fprintf('Контрольные точки: два набора, %d и %d пар.\n\n', ...
    numPairsSmall,numPairsLarge);

% Координаты точек выводятся в консоль и попадут в PDF.
fprintf('   № | moving x | moving y | fixed x | fixed y\n');
fprintf('-----+----------+----------+---------+---------\n');
for k = 1:numPairsLarge
    j = selected(k);
    fprintf('%4d | %8.2f | %8.2f | %7.2f | %7.2f\n', ...
        k,movingInliers(j,1),movingInliers(j,2), ...
        fixedInliers(j,1),fixedInliers(j,2));
end
fprintf('\n');

figure('Name','03 - Контрольные точки','Color','w');
showMatchedFeatures(distorted,original, ...
    movingInliers(selected,:),fixedInliers(selected,:), ...
    'montage','PlotOptions',{'yo','go','y-'});
title('10 пар контрольных точек (первые 5 используются в обоих опытах)');

%% 4–7. Оценка подобия, обратное преобразование, восстановление
Roriginal = imref2d(size(original));
counts = [numPairsSmall numPairsLarge];
recoveredImages = cell(1,2);
results = zeros(2,7); % [N, scaleInv, angleInv, errScale, errAngle, RMSE, MAE]

for trial = 1:2
    n = counts(trial);
    idx = selected(1:n);
    movingPoints = movingInliers(idx,:);
    fixedPoints = fixedInliers(idx,:);

    % Преобразование distorted -> original.
    tform = fitgeotform2d(movingPoints,fixedPoints,'similarity');
    % Обратное original -> distorted: сравниваем с параметрами искажения.
    tformInv = invert(tform);
    foundScale = tformInv.Scale;
    foundAngle = tformInv.RotationAngle;
    % В геометрических координатах угол имеет знак, обратный imrotate.
    expectedAngle = -theta;
    angleError = mod(foundAngle-expectedAngle+180,360)-180;

    recovered = imwarp(distorted,tform,'OutputView',Roriginal);
    recoveredImages{trial} = recovered;

    % Оценка на валидных пикселях: маска исключает фон вне кадра.
    % Маску преобразуем с той же геометрией, что и изображение.
    validDistorted = imrotate(ones(size(scaled),'uint8'), ...
        theta,'nearest','loose') > 0;
    validRecovered = imwarp(validDistorted,tform,'nearest', ...
        'OutputView',Roriginal);
    pixelsA = double(original(validRecovered));
    pixelsB = double(recovered(validRecovered));
    if isempty(pixelsA)
        error('После регистрации не осталось общей области изображений.');
    end
    rmse = sqrt(mean((pixelsA-pixelsB).^2));
    mae  = mean(abs(pixelsA-pixelsB));
    results(trial,:) = [n,foundScale,foundAngle, ...
        abs(foundScale-scaleFactor),abs(angleError),rmse,mae];

    fprintf('=== Регистрация по %d парам ===\n',n);
    fprintf('tformInv.Scale = %.6f (исходный масштаб = %.6f)\n', ...
        foundScale,scaleFactor);
    fprintf('tformInv.RotationAngle = %.4f° (ожидалось %.4f°)\n', ...
        foundAngle,expectedAngle);
    fprintf('Ошибка масштаба = %.6f; ошибка угла = %.4f°\n', ...
        abs(foundScale-scaleFactor),abs(angleError));
    fprintf('RMSE в области перекрытия = %.4f; MAE = %.4f; пикселей = %d\n\n', ...
        rmse,mae,numel(pixelsA));
    fprintf('Матрица преобразования distorted -> original:\n');
    disp(tform.A);

    figure('Name',sprintf('0%d - Восстановление %d точек',3+trial,n), ...
        'Color','w');
    montage({original,recovered});
    title(sprintf('Слева исходное, справа восстановленное (%d пар, RMSE=%.3f)', ...
        n,rmse));
end

%% 8. Сравнение точности для 5 и 10 пар
figure('Name','06 - Сравнение результатов','Color','w');
montage({original,recoveredImages{1},recoveredImages{2}});
title('Слева: оригинал; центр: 5 пар; справа: 10 пар');

figure('Name','07 - Погрешности регистрации','Color','w');
tiledlayout(1,2,'Padding','compact');
nexttile;
plot(counts,results(:,6),'-o','LineWidth',1.8,'MarkerSize',8);
xticks(counts); grid on;
xlabel('Число пар контрольных точек'); ylabel('RMSE, уровни яркости');
title('Ошибка восстановления');
nexttile;
plot(counts,results(:,5),'-s','LineWidth',1.8,'MarkerSize',8);
xticks(counts); grid on;
xlabel('Число пар контрольных точек'); ylabel('Ошибка угла, градусы');
title('Ошибка оценки угла');

fprintf('=== Сводная таблица ===\n');
fprintf('Пар | Scale    | Angle, град | RMSE     | MAE\n');
for k = 1:2
    fprintf('%3d | %8.5f | %11.4f | %8.4f | %8.4f\n', ...
        results(k,1),results(k,2),results(k,3),results(k,6),results(k,7));
end
fprintf('\nВывод: ');
if results(2,6) < results(1,6)
    fprintf('при 10 парах RMSE снизилась относительно 5 пар.\n');
elseif results(2,6) > results(1,6)
    fprintf('при 10 парах RMSE выросла: увеличение числа точек само по себе не гарантирует улучшения.\n');
else
    fprintf('RMSE совпала для двух наборов.\n');
end
fprintf(['Точность зависит также от локализации, распределения и качества ' ...
    'контрольных точек, интерполяции и потерь при уменьшении.\n']);
fprintf('Для imrotate положительный угол направлен против часовой стрелки,\n');
fprintf('а RotationAngle в координатах изображения имеет обратный знак.\n');
fprintf('OutputView фиксирует размер результата по исходному изображению.\n');
fprintf('Все результирующие Figure оставлены открытыми для make_report.\n');
