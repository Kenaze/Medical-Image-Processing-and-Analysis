clc;
clear;
close all;

%% 1. Загрузка исходного изображения
filename = '07_Variant.jpg';
I = imread(filename);

figure;
imshow(I);
title('Исходное изображение');

%% 2. Информация о введенном файле
disp('Информация о файле:');
info = imfinfo(filename);
disp(info);

%% 3. Негативное изображение
Ineg = imcomplement(I);

figure;
imshow(Ineg);
title('Негативное изображение');

%% 4. Проверка: полноцветное изображение или полутоновое
if ndims(I) == 3 && size(I,3) == 3
    disp('Исходное изображение является полноцветным');
    Igray = rgb2gray(I);
else
    disp('Исходное изображение является полутоновым');
    Igray = I;
end

figure;
imshow(Igray);
title('Полутоновое изображение');

%% 5. Изменение яркости
% gamma < 1 — изображение светлее
Ilight = imadjust(Igray, [], [], 0.5);

figure;
imshow(Ilight);
title('Более светлое изображение');

% gamma > 1 — изображение темнее
Idark = imadjust(Igray, [], [], 2);

figure;
imshow(Idark);
title('Более темное изображение');

%% 6. Бинаризация изображения
level = graythresh(Igray);
BW = im2bw(Igray, level);

figure;
imshow(BW);
title('Бинарное изображение');

% Если на полученном изображении фон белый, а объекты черные,
% перед bwlabel следует раскомментировать следующую строку:
% BW = ~BW;

%% Определение объектов при связности 4
[L4, numObjects4] = bwlabel(BW, 4);

P4 = label2rgb(L4, @spring, 'c', 'shuffle');

figure;
imshow(P4);
title('Матрица меток, связность 4');

%% Определение объектов при связности 8
[L8, numObjects8] = bwlabel(BW, 8);

P8 = label2rgb(L8, @spring, 'c', 'shuffle');

figure;
imshow(P8);
title('Матрица меток, связность 8');

%% 7. Гистограммы всех изображений

% Исходное изображение
figure;
if ndims(I) == 3
    imhist(rgb2gray(I));
else
    imhist(I);
end
title('Гистограмма исходного изображения');

% Негатив
figure;
if ndims(Ineg) == 3
    imhist(rgb2gray(Ineg));
else
    imhist(Ineg);
end
title('Гистограмма негативного изображения');

% Полутоновое
figure;
imhist(Igray);
title('Гистограмма полутонового изображения');

% Светлое
figure;
imhist(Ilight);
title('Гистограмма светлого изображения');

% Темное
figure;
imhist(Idark);
title('Гистограмма темного изображения');

% Бинарное
figure;
imhist(BW);
title('Гистограмма бинарного изображения');

% Псевдоцветное изображение для связности 4
figure;
imhist(rgb2gray(P4));
title('Гистограмма матрицы меток, связность 4');

% Псевдоцветное изображение для связности 8
figure;
imhist(rgb2gray(P8));
title('Гистограмма матрицы меток, связность 8');

%% 8. Информация обо всех переменных
disp('Информация обо всех переменных:');
whos

%% 9. Число объектов при разных связностях
fprintf('\nКоличество объектов при связности 4: %d\n', numObjects4);
fprintf('Количество объектов при связности 8: %d\n', numObjects8);