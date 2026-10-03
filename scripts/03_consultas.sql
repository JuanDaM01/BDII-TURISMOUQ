SET DEFINE OFF


-- CONSULTA 1 Ocupacion por municipio y mes con PIVOT
-- Pregunta: ¿Cuantas noches de habitacion se reservaron en cada municipio, mes por mes durante 2025?

SELECT *
  FROM (SELECT mu.nombre AS municipio,
               EXTRACT(MONTH FROM rh.check_in) AS mes,
               rh.check_out - rh.check_in AS noches
        FROM reserva_habitacion rh
        JOIN reserva r ON r.id_reserva = rh.id_reserva
        JOIN alojamiento a ON a.id_alojamiento = rh.id_alojamiento
        JOIN municipio mu ON mu.id_municipio = a.id_municipio
        WHERE r.estado <> 'CANCELADA' AND EXTRACT(YEAR FROM rh.check_in) = 2025)
PIVOT (SUM(noches) FOR mes IN 
    (1 AS ene, 2 AS feb, 3 AS mar, 4 AS abr, 5 AS may, 6 AS jun,
     7 AS jul, 8 AS ago, 9 AS sep, 10 AS oct, 11 AS nov, 12 AS dic))
ORDER BY municipio;


-- CONSULTA 2 Ingresos por municipio, tipo y temporada usando ROLLUP y GROUPING
-- Pregunta: ¿Cuanto dinero generaron las reservas completadas por municipio, por tipo de alojamiento y por temporada (alta, media, baja)? 
-- Incluir subtotales por municipio y el total general
 
SELECT CASE WHEN GROUPING(mu.nombre) = 1 THEN 'TOTAL GENERAL' ELSE mu.nombre END AS municipio,
       CASE WHEN GROUPING(ta.nombre) = 1 THEN 'Todos los tipos' ELSE ta.nombre END AS tipo_alojamiento,
       CASE WHEN GROUPING(t.nivel) = 1 THEN 'Todas las temporadas' ELSE t.nivel END AS temporada,
       SUM(rh.valor_estadia) AS ingresos
  FROM reserva_habitacion rh
  JOIN reserva r ON r.id_reserva = rh.id_reserva
  JOIN alojamiento a ON a.id_alojamiento = rh.id_alojamiento
  JOIN municipio mu ON mu.id_municipio = a.id_municipio
  JOIN tipo_alojamiento ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
  JOIN temporada t ON rh.check_in BETWEEN t.fecha_inicio AND t.fecha_fin
WHERE r.estado = 'COMPLETADA'
GROUP BY ROLLUP (mu.nombre, ta.nombre, t.nivel)
ORDER BY GROUPING(mu.nombre), mu.nombre, GROUPING(ta.nombre), ta.nombre, GROUPING(t.nivel), t.nivel;


-- CONSULTA 3 Los 3 alojamientos de mayor ingreso por municipio usando RANK con PARTITION BY
-- Pregunta: ¿Cuales son los 3 alojamientos que mas dinero generaron en cada municipio?

SELECT municipio, posicion, alojamiento, ingresos
    FROM (SELECT mu.nombre AS municipio,
               a.nombre_comercial AS alojamiento,
               SUM(rh.valor_estadia) AS ingresos,
               RANK() OVER (PARTITION BY mu.nombre ORDER BY SUM(rh.valor_estadia) DESC) AS posicion
          FROM reserva_habitacion rh
          JOIN reserva r ON r.id_reserva = rh.id_reserva
          JOIN alojamiento a ON a.id_alojamiento = rh.id_alojamiento
          JOIN municipio mu ON mu.id_municipio = a.id_municipio
          WHERE r.estado = 'COMPLETADA'
          GROUP BY mu.nombre, a.nombre_comercial)
WHERE posicion <= 3
ORDER BY municipio, posicion;


-- CONSULTA 4 Variacion de ingresos mes contra mes con LAG
-- Pregunta: ¿Cuanto dinero se genero cada mes y cuanto subio o bajo frente al mes anterior?

SELECT mes, ingresos,
       LAG(ingresos) OVER (ORDER BY mes) AS mes_anterior,
       ingresos - LAG(ingresos) OVER (ORDER BY mes) AS variacion,
       ROUND(100 * (ingresos - LAG(ingresos) OVER (ORDER BY mes))
        / LAG(ingresos) OVER (ORDER BY mes), 1) AS variacion_pct
    FROM (SELECT TO_CHAR(rh.check_in, 'YYYY-MM') AS mes,
               SUM(rh.valor_estadia) AS ingresos
          FROM reserva_habitacion rh
          JOIN reserva r ON r.id_reserva = rh.id_reserva
          WHERE r.estado = 'COMPLETADA'
         GROUP BY TO_CHAR(rh.check_in, 'YYYY-MM'))
  ORDER BY mes;


-- CONSULTA 5 Consulta parametrizada
-- Pregunta: Si se elije una fecha inicial y una final, ¿cuanto dinero genero cada municipio con las reservas cuyo check-in cae entre esas fechas?

VARIABLE f_ini VARCHAR2(10)
VARIABLE f_fin VARCHAR2(10)
BEGIN
  :f_ini := '2025-12-15';
  :f_fin := '2026-01-10';
END;
/

SELECT mu.nombre AS municipio,
       COUNT(DISTINCT r.id_reserva) AS reservas,
       SUM(rh.valor_estadia) AS ingresos
FROM reserva_habitacion rh
JOIN reserva r ON r.id_reserva = rh.id_reserva
JOIN alojamiento a ON a.id_alojamiento = rh.id_alojamiento
JOIN municipio mu ON mu.id_municipio = a.id_municipio
WHERE r.estado = 'COMPLETADA' AND 
  rh.check_in BETWEEN TO_DATE(:f_ini, 'YYYY-MM-DD') AND TO_DATE(:f_fin, 'YYYY-MM-DD')
GROUP BY mu.nombre
ORDER BY ingresos DESC;


-- CONSULTA 6 UNPIVOT
-- Pregunta: ¿Cuantas reservas tiene cada municipio en cada estado (completada, confirmada, pendiente, cancelada)? 
-- Mostrar una fila por municipio y estado

SELECT municipio, estado, reservas
    FROM (SELECT mu.nombre AS municipio,
               SUM(CASE WHEN r.estado = 'COMPLETADA' THEN 1 ELSE 0 END) AS completadas,
               SUM(CASE WHEN r.estado = 'CONFIRMADA' THEN 1 ELSE 0 END) AS confirmadas,
               SUM(CASE WHEN r.estado = 'PENDIENTE' THEN 1 ELSE 0 END) AS pendientes,
               SUM(CASE WHEN r.estado = 'CANCELADA' THEN 1 ELSE 0 END) AS canceladas
          FROM reserva r
          JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
          JOIN municipio mu  ON mu.id_municipio = a.id_municipio
          GROUP BY mu.nombre)
 UNPIVOT (reservas FOR estado IN 
    (completadas AS 'COMPLETADA', confirmadas AS 'CONFIRMADA',
     pendientes  AS 'PENDIENTE', canceladas  AS 'CANCELADA'))
 ORDER BY municipio, estado;


-- CONSULTA 7 Consulta libre
-- Pregunta de negocio: ¿Cuales son los 10 alojamientos mejor calificados por sus clientes? 
-- Solo cuentan los que tienen al menos 10 reseñas para que el promedio sea confiable

SELECT a.nombre_comercial AS alojamiento, mu.nombre  AS municipio,
       COUNT(*) AS resenas,
       ROUND(AVG(rs.calificacion), 2) AS calificacion_promedio
FROM resena rs
JOIN reserva r     ON r.id_reserva = rs.id_reserva
JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
JOIN municipio mu  ON mu.id_municipio = a.id_municipio
GROUP BY a.nombre_comercial, mu.nombre
HAVING COUNT(*) >= 10
ORDER BY calificacion_promedio DESC, resenas DESC
FETCH FIRST 10 ROWS ONLY;
