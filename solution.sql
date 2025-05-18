
--Этап 1. Создание и заполнение БД
--------------------------------------------------------------------------------------------------------
-- Создание схемы raw_data для хранения сырых данных
CREATE SCHEMA IF NOT EXISTS raw_data;


-- Создание таблицы для хранение сырых данных
CREATE TABLE IF NOT EXISTS raw_data.sales(
	id INT PRIMARY KEY,
	auto VARCHAR(100) NOT NULL,
	gasoline_consumption NUMERIC(3,1) DEFAULT NULL CHECK(gasoline_consumption > 0),
	price NUMERIC(9, 2) NOT NULL CHECK(price >= 0),
	date_sale DATE NOT NULL,
	person_name VARCHAR(40) NOT NULL,
	phone VARCHAR(40) NOT NULL,
	discount SMALLINT DEFAULT 0 CHECK(discount BETWEEN 0 AND 100),
	brand_origin VARCHAR(70) DEFAULT NULL
);


-- Создание схемы для хранение нормализованных таблиц
CREATE SCHEMA IF NOT EXISTS car_shop;


-- Создание таблицы бренда автомобиля
CREATE TABLE IF NOT EXISTS car_shop.car_brand(
	brand_id SERIAL PRIMARY KEY, 
	brand_name VARCHAR(30) NOT NULL UNIQUE, /*- Название бренда ограничение 30 символов.
	Бренд может быть только один для данной таблицы и не может быть равен NULL */
	country VARCHAR(70) DEFAULT NULL   /*Ограничение 70 символов для страны.
	По умолчанию может быть NULL*/
);


-- Создание таблицы всех цветов, встречающихся в сырой бд
CREATE TABLE IF NOT EXISTS car_shop.colors(
	color_id SERIAL PRIMARY KEY,
	color_name VARCHAR(30) NOT NULL UNIQUE /*Ограничение 30 символов для цвета.
	Цвет не может быть равен нулю и должен быть уникальным.*/
);


-- Создание таблицы клиентов
CREATE TABLE IF NOT EXISTS car_shop.clients(
	client_id SERIAL PRIMARY KEY,
	first_name VARCHAR(30) NOT NULL,  /*Для имени ограничение 30 символов*/
	second_name VARCHAR(30) NOT NULL, /*Для фамилии ограничение 30 символов*/
	phone_number TEXT NOT NULL UNIQUE /*Номерт телефона клиентов допускаю в разных форматах.
	Не может быть равен нулю и у одного клиента уникальный номер.*/
);




--------------------------------------------------------------------------------------------------------
/*Перед тем как создавать остальные таблицы я сначала проверяю, что данные
 корректно загружаются в родительские таблицы.*/


-- Вставляем данные в car_brand
INSERT INTO car_shop.car_brand(brand_name, country)
SELECT DISTINCT
	SPLIT_PART(s.auto, ' ', 1), /*В сыром виде бренд хранится в одной строке, разделенной пробелами*/
	s.brand_origin 				/*Страна хранится просто в отдельной колонке*/
FROM raw_data.sales AS s
/*Возвращаем результат чтобы убедиться что все работает правильно*/
RETURNING *;


-- Вставляем данные о цветах
INSERT INTO car_shop.colors(color_name)
SELECT DISTINCT
	SPLIT_PART(s.auto, ', ', 2) /*Цвет хранится вторым после запятой*/
FROM raw_data.sales AS s
/*Возвращаем результат чтобы убедиться что все работает правильно*/
RETURNING *;


-- Вставляем данные о клиентах
INSERT INTO car_shop.clients(first_name, second_name, phone_number)
SELECT DISTINCT
	CASE
		-- В сыром виде могут встречаться ненужные строки перед именем
		WHEN SPLIT_PART(s.person_name, ' ', 1) IN ('Dr.', 'Mrs.', 'Mr.') 
        THEN SPLIT_PART(s.person_name, ' ', 2) /*Если строка есть, то имя идет вторым*/
        ELSE SPLIT_PART(s.person_name, ' ', 1) /*Иначе первым*/
	END AS first_name,
	CASE
        WHEN SPLIT_PART(s.person_name, ' ', 1) IN ('Dr.', 'Mrs.', 'Mr.')
        THEN SPLIT_PART(s.person_name, ' ', 3) /*Если строка есть, то фамилия идет третьей*/
        ELSE SPLIT_PART(s.person_name, ' ', 2) /*Иначе второй*/
    END AS second_name,
    s.phone /*Беру телефон как есть без манипуляций*/
FROM raw_data.sales AS s
/*Возвращаем результат чтобы убедиться что все работает правильно*/
RETURNING *;
--------------------------------------------------------------------------------------------------------
--Продолжаю создавать таблицы




-- Создание таблицы моделей автомобиля
CREATE TABLE IF NOT EXISTS car_shop.car_model(
	model_id SERIAL PRIMARY KEY,
	/*Для моделей взял максимаальный размер 50. Название модели уникально*/
	model_name VARCHAR(50) NOT NULL UNIQUE, 
	/*Ссылка на бренд. Нельзя удалить бренд если он используется в моделях*/
	brand_id INT NOT NULL REFERENCES car_shop.car_brand(brand_id) ON DELETE RESTRICT,
	/*Для литража использую NUMERIC в диапозоне от 0 до 99.9.
	  CHECK не даёт вставить 0 или отрицательные значения.*/
	gasoline_consumption NUMERIC(3, 1) DEFAULT NULL CHECK(gasoline_consumption > 0)
);


-- Сразу добавляю данные в модели автомобилей
INSERT INTO car_shop.car_model (model_name, brand_id, gasoline_consumption)
SELECT DISTINCT
	/*Использую TRIM в связке с LOWER и REPLACE чтобы извлечь название модели*/
	TRIM(INITCAP(TRIM(LOWER(REPLACE(s.auto, ',', ' ')), 'abcdefghijklmnopqrstuvwxyz')), ' ') AS model_name,
	/*Записываю id модели*/
	cb.brand_id,
	/*Литраж. Может быть NULL если электрокар*/
	s.gasoline_consumption
FROM raw_data.sales AS s
LEFT JOIN car_shop.car_brand AS cb ON SPLIT_PART(s.auto, ' ', 1) = cb.brand_name
RETURNING *;



-- Создаем таблицу sales
CREATE TABLE IF NOT EXISTS car_shop.sales(
	sale_id SERIAL PRIMARY KEY,
	/*Модель продаваемого автомобиля не может быть NULL. Запрет на удаление если есть зависимость*/
	model_id INT NOT NULL REFERENCES car_shop.car_model(model_id) ON DELETE RESTRICT,
	/*Цвет не может быть NULL*/
	color_id INT NOT NULL REFERENCES car_shop.colors(color_id) ON DELETE RESTRICT,
	/*Покупатель не может быть NULL. Запрет на удаление если есть зависимость*/
	client_id INT NOT NULL REFERENCES car_shop.clients(client_id) ON DELETE RESTRICT,
	/*Цена не может быть равна 0. Я понимаю что с discount = 100 это будет странно,
	  но решил оставить так, чтобы выгрузить все данные без потерь. Можно в будущем скорректировать этот параметр */
	price NUMERIC(9, 2) NOT NULL CHECK(price > 0),
	/*Скидка по умолчанию 0 либо проверка чтобы она находилась в диапазоне от 0 до 100*/
	discount SMALLINT DEFAULT 0 CHECK(discount BETWEEN 0 AND 100),
	/*Обязательная информация о дате*/
	date_sale DATE NOT NULL
);


-- Вставляем данные в sales
INSERT INTO car_shop.sales (model_id, color_id, client_id, price, discount, date_sale)
SELECT
	cm.model_id,
	c.color_id,
	cl.client_id,
	s.price,
	s.discount,
	s.date_sale
FROM raw_data.sales AS s
/*Если данные не с чем будет связать будет ошибка, которая будет указывать на то что поле не может быть NULL*/
LEFT JOIN car_shop.car_model AS cm 
	ON cm.model_name = TRIM(INITCAP(TRIM(LOWER(REPLACE(s.auto, ',', ' ')), 'abcdefghijklmnopqrstuvwxyz')), ' ') 
LEFT JOIN car_shop.colors AS c
	ON c.color_name = SPLIT_PART(s.auto, ', ', 2)	
LEFT JOIN car_shop.clients AS cl
	ON cl.phone_number = s.phone
RETURNING *;







--Этап 2. Создание выборок
--------------------------------------------------------------------------------------------------------


-- Задача 1
/*Напишите запрос, который выведет процент моделей машин,
  у которых нет параметра gasoline_consumption.*/

SELECT ROUND (
COUNT (CASE WHEN cm.gasoline_consumption IS NULL THEN 1 END)
* 100 / COUNT(*)::decimal, 2) 
AS nulls_percentage_gasoline_consumption
FROM car_shop.sales AS s
INNER JOIN car_shop.car_model AS cm USING(model_id);


-- Задача 2
/*Напишите запрос, который покажет название бренда и среднюю цену его автомобилей в разбивке по всем годам 
  с учётом скидки. Итоговый результат отсортируйте по названию бренда и году в восходящем порядке. 
  Среднюю цену округлите до второго знака после запятой.*/

SELECT 
	cb.brand_name, 
	EXTRACT(YEAR FROM s.date_sale) AS year, 
	ROUND(AVG(s.price), 2) AS price_avg
FROM car_shop.sales AS s 
LEFT JOIN car_shop.car_model AS cm USING(model_id)
LEFT JOIN car_shop.car_brand AS cb USING(brand_id)
GROUP BY cb.brand_name, year
ORDER BY cb.brand_name, year;


-- Задача 3
/*Посчитайте среднюю цену всех автомобилей с разбивкой по месяцам в 2022 году с учётом скидки. 
  Результат отсортируйте по месяцам в восходящем порядке. 
  Среднюю цену округлите до второго знака после запятой.*/

SELECT 
	EXTRACT(MONTH FROM s.date_sale) AS month,
	EXTRACT(YEAR FROM s.date_sale) AS year,
	ROUND(AVG(s.price), 2) AS price_avg
FROM car_shop.sales AS s 
WHERE EXTRACT(YEAR FROM s.date_sale) = 2022
GROUP BY month, year
ORDER BY year, MONTH;


-- Задача 4
/*Используя функцию STRING_AGG, напишите запрос, 
  который выведет список купленных машин у каждого пользователя через запятую. 
  Пользователь может купить две одинаковые машины — это нормально. 
  Название машины покажите полное, с названием бренда — например: Tesla Model 3. 
  Отсортируйте по имени пользователя в восходящем порядке. Сортировка внутри самой строки с машинами не нужна.*/

SELECT
	c.first_name || ' ' || c.second_name AS person,
	STRING_AGG(cb.brand_name || ' '  || cm.model_name, ', ') AS cars
FROM car_shop.clients AS c
LEFT JOIN car_shop.sales AS s USING(client_id) 
LEFT JOIN car_shop.car_model AS cm USING(model_id)
LEFT JOIN car_shop.car_brand AS cb USING(brand_id) 
GROUP BY c.first_name, c.second_name
ORDER BY person;



-- Задача 5
/*Напишите запрос, который вернёт самую большую и самую маленькую цену продажи автомобиля
  с разбивкой по стране без учёта скидки. Цена в колонке price дана с учётом скидки.*/

SELECT
	cb.country AS brand_origin,
	-- Деление на 0 не будет потому что при создании таблицы есть ограничение 
	-- discount SMALLINT DEFAULT 0 CHECK(discount BETWEEN 0 AND 100),
	ROUND(MAX(s.price / (1 - s.discount / 100)::decimal), 2) AS price_max,
	ROUND(MIN(s.price / (1 - s.discount / 100)::decimal), 2) AS price_min
FROM car_shop.sales AS s
LEFT JOIN car_shop.car_model AS cm USING(model_id)
LEFT JOIN car_shop.car_brand AS cb USING(brand_id)
-- Я не стал брать страну если её значение NULL
WHERE cb.country IS NOT NULL
GROUP BY cb.country;



-- Задача 6
/*Напишите запрос, который покажет количество всех пользователей из США. 
  Это пользователи, у которых номер телефона начинается на +1.*/

SELECT
	COUNT(*) AS persons_from_usa_count
FROM car_shop.clients AS c
WHERE SUBSTR(c.phone_number ,1, 2) = '+1';
