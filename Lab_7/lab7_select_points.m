%% Лабораторная работа № 7: ручной выбор углов
% Запустить отдельно до make_report("lab7_manual.m").
% Выбрать мышью ЛВ, ЛН, ПН, ПВ одной плоской области.
clc;
close all;
imageFile = 'V07.jpg';
if ~isfile(imageFile)
    error('lab7:FileNotFound','Не найден файл %s.',imageFile);
end
img = imread(imageFile);
[imgHeight,imgWidth,~] = size(img);
figure('Name','Выбор углов','Color','w','Position',[100 100 1100 720]);
imshow(img,'InitialMagnification','fit');
title({'Выберите четыре угла одной плоской области', ...
       'Порядок: левый верхний, левый нижний, правый нижний, правый верхний'}, ...
       'Interpreter','none');
hold on;
movingPoints = zeros(4,2);
names = {'ЛВ','ЛН','ПН','ПВ'};
for k = 1:4
    fprintf('Щёлкните точку %d (%s)...\n',k,names{k});
    [x,y,button] = ginput(1);
    if isempty(button) || ~isfinite(x) || ~isfinite(y)
        error('lab7:Cancelled','Выбор отменён.');
    end
    if x<1 || x>imgWidth || y<1 || y>imgHeight
        error('lab7:OutOfBounds','Точка за пределами изображения. Повторите выбор.');
    end
    movingPoints(k,:) = [x y];
    plot(x,y,'ro','MarkerFaceColor','r','MarkerSize',9);
    text(x+6,y,sprintf('%d %s',k,names{k}), ...
        'Color','yellow','FontWeight','bold','BackgroundColor','black');
    drawnow;
end
outline = [movingPoints; movingPoints(1,:)];
plot(outline(:,1),outline(:,2),'y-','LineWidth',2);
edges = diff(outline,1,1);
crossZ = edges(:,1).*edges([2 3 4 1],2) - ...
         edges(:,2).*edges([2 3 4 1],1);
if ~(all(crossZ>0) || all(crossZ<0))
    error('lab7:InvalidQuadrilateral', ...
        'Точки должны образовывать выпуклый четырёхугольник. Повторите выбор.');
end
selectedImageFile = imageFile;
selectedImageSize = [imgHeight imgWidth];
save('lab7_points.mat','movingPoints','selectedImageFile','selectedImageSize');
fprintf('Точки сохранены в lab7_points.mat\n');
disp(movingPoints);
fprintf('Теперь выполните make_report("lab7_manual.m")\n');
