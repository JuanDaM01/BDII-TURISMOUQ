SET SERVEROUTPUT ON
SET DEFINE OFF


-- SECCION 1: fn_valor_estadia

-- 1.1 Desglose noche por noche de una estadia que cruza temporadas (10 al 18 de diciembre de 2025)
SELECT TO_CHAR(n.noche, 'YYYY-MM-DD') AS noche,
       t.nombre AS temporada,
       t.nivel,
       ta.valor_noche
  FROM (SELECT DATE '2025-12-10' + LEVEL - 1 AS noche
          FROM dual
        CONNECT BY LEVEL <= DATE '2025-12-18' - DATE '2025-12-10') n
  JOIN temporada t ON n.noche BETWEEN t.fecha_inicio AND t.fecha_fin
  JOIN tarifa ta   ON ta.id_temporada = t.id_temporada
 WHERE ta.id_habitacion = (SELECT MIN(id_habitacion) FROM habitacion)
 ORDER BY n.noche;

-- 1.2 La funcion contra la suma del desglose anterior
DECLARE
  v_hab NUMBER;
  v_fn  NUMBER;
  v_sql NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
  v_fn := pkg_reservas.fn_valor_estadia(v_hab, DATE '2025-12-10', DATE '2025-12-18');

  SELECT SUM(ta.valor_noche)
    INTO v_sql
    FROM (SELECT DATE '2025-12-10' + LEVEL - 1 AS noche
            FROM dual
          CONNECT BY LEVEL <= DATE '2025-12-18' - DATE '2025-12-10') n
    JOIN temporada t ON n.noche BETWEEN t.fecha_inicio AND t.fecha_fin
    JOIN tarifa ta   ON ta.id_temporada = t.id_temporada
   WHERE ta.id_habitacion = v_hab;

  DBMS_OUTPUT.PUT_LINE('1.2 Estadía que cruza temporadas, habitación ' || v_hab ||
                       ': fn_valor_estadia = ' || v_fn ||
                       ' | suma noche a noche en SQL = ' || v_sql || ' -> ' ||
                       CASE WHEN v_fn = v_sql THEN 'COINCIDEN' ELSE 'DIFERENTES' END);
END;
/

-- 1.3 Estadia dentro de una sola temporada (3 al 6 de marzo de 2025, tres noches con la misma tarifa)
DECLARE
  v_hab NUMBER;
  v_fn  NUMBER;
  v_sql NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
  v_fn := pkg_reservas.fn_valor_estadia(v_hab, DATE '2025-03-03', DATE '2025-03-06');

  SELECT 3 * ta.valor_noche
    INTO v_sql
    FROM temporada t
    JOIN tarifa ta ON ta.id_temporada = t.id_temporada
   WHERE ta.id_habitacion = v_hab
     AND DATE '2025-03-03' BETWEEN t.fecha_inicio AND t.fecha_fin
     AND DATE '2025-03-05' BETWEEN t.fecha_inicio AND t.fecha_fin;

  DBMS_OUTPUT.PUT_LINE('1.3 Una sola temporada: fn_valor_estadia = ' || v_fn ||
                       ' | 3 x tarifa de la temporada = ' || v_sql || ' -> ' ||
                       CASE WHEN v_fn = v_sql THEN 'COINCIDEN' ELSE 'DIFERENTES' END);
END;
/

-- 1.4 Check-out igual al check-in
DECLARE
  v_hab NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
  DBMS_OUTPUT.PUT_LINE('1.4 Resultado: ' ||
    pkg_reservas.fn_valor_estadia(v_hab, DATE '2025-03-03', DATE '2025-03-03'));
EXCEPTION
  WHEN pkg_reservas.e_checkout_invalido THEN
    DBMS_OUTPUT.PUT_LINE('1.4 Error esperado: ' || SQLERRM);
END;
/

-- 1.5 La funcion contra el valor guardado por la carga en 5.000 lineas (diferencias debe ser 0)
SELECT COUNT(*) AS lineas_revisadas,
       SUM(CASE WHEN pkg_reservas.fn_valor_estadia(id_habitacion, check_in, check_out) = valor_estadia
                THEN 0 ELSE 1 END) AS diferencias
  FROM (SELECT id_habitacion, check_in, check_out, valor_estadia
          FROM reserva_habitacion
         ORDER BY id_reserva_habitacion
         FETCH FIRST 5000 ROWS ONLY);


-- SECCION 2: sp_crear_reserva
-- Habitacion y cliente de menor id; reservas de prueba en enero de 2027, que la carga deja libre.
-- Los casos comparten la transaccion: el 2.1 deja una reserva que hace rechazar al 2.2 y al 2.3

DECLARE
  v_hab NUMBER;
  v_cli NUMBER;
  v_cap NUMBER;
  v_id  NUMBER;

  PROCEDURE intentar (p_caso VARCHAR2, p_hab NUMBER, p_in DATE, p_out DATE, p_hue NUMBER) IS
  BEGIN
    pkg_reservas.sp_crear_reserva(v_cli, p_hab, p_in, p_out, p_hue, v_id);
    DBMS_OUTPUT.PUT_LINE(p_caso || ' -> CREADA, id_reserva ' || v_id);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(p_caso || ' -> RECHAZADA: ' || SQLERRM);
  END intentar;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
  SELECT capacidad INTO v_cap FROM habitacion WHERE id_habitacion = v_hab;
  SELECT MIN(id_cliente) INTO v_cli FROM cliente;
  DBMS_OUTPUT.PUT_LINE('Habitación de prueba ' || v_hab || ' (capacidad ' || v_cap || '), cliente ' || v_cli);

  intentar('2.1 Reserva válida del 9 al 14 de enero de 2027 (cruza temporadas)', v_hab, DATE '2027-01-09', DATE '2027-01-14', 1);
  intentar('2.2 Misma habitación y mismas fechas', v_hab, DATE '2027-01-09', DATE '2027-01-14', 1);
  intentar('2.3 Cruce parcial, del 12 al 16 de enero', v_hab, DATE '2027-01-12', DATE '2027-01-16', 1);
  intentar('2.4 Check-out igual al check-in', v_hab, DATE '2027-01-20', DATE '2027-01-20', 1);
  intentar('2.5 Check-out anterior al check-in', v_hab, DATE '2027-01-22', DATE '2027-01-20', 1);
  intentar('2.6 Capacidad excedida (huéspedes = capacidad + 1)', v_hab, DATE '2027-01-20', DATE '2027-01-22', v_cap + 1);
  intentar('2.7 Habitación inexistente', 999999999, DATE '2027-01-20', DATE '2027-01-22', 1);
  intentar('2.8 Reserva contigua, empieza el día en que termina la anterior (permitida)', v_hab, DATE '2027-01-14', DATE '2027-01-16', 1);
END;
/

-- 2.9 Reservas registradas: deben ser dos (2.1 y 2.8), con el valor calculado por la funcion
SELECT r.id_reserva, r.estado, r.fecha_reserva, r.check_in, r.check_out,
       rh.id_habitacion, rh.huespedes, rh.valor_estadia
  FROM reserva r
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
 WHERE r.check_in >= DATE '2027-01-01'
 ORDER BY r.id_reserva;


-- SECCION 3: Disparador de fila, solape de reservas
-- INSERT y UPDATE directos sobre RESERVA_HABITACION, sin pasar por sp_crear_reserva.
-- Siguen en la transaccion de la seccion 2: ya existen las reservas del 9 al 14 y del 14 al 16 de enero

DECLARE
  v_hab  NUMBER;
  v_aloj NUMBER;
  v_cli  NUMBER;
  v_res  NUMBER;
  v_lin  NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
  SELECT id_alojamiento INTO v_aloj FROM habitacion WHERE id_habitacion = v_hab;
  SELECT MIN(id_cliente) INTO v_cli FROM cliente;

  -- 3.1 INSERT que se cruza con la reserva del 9 al 14
  INSERT INTO reserva (id_cliente, id_alojamiento, fecha_reserva, check_in, check_out, estado)
  VALUES (v_cli, v_aloj, TRUNC(SYSDATE), DATE '2027-01-12', DATE '2027-01-16', 'CONFIRMADA')
  RETURNING id_reserva INTO v_res;

  BEGIN
    INSERT INTO reserva_habitacion (id_reserva, id_habitacion, id_alojamiento,
                                    check_in, check_out, huespedes, valor_estadia)
    VALUES (v_res, v_hab, v_aloj, DATE '2027-01-12', DATE '2027-01-16', 1, 100000);
    DBMS_OUTPUT.PUT_LINE('3.1 FALLÓ: el disparador permitió el solape');
  EXCEPTION
    WHEN pkg_reservas.e_solape_reserva THEN
      DBMS_OUTPUT.PUT_LINE('3.1 BLOQUEADO por el disparador: ' || SQLERRM);
  END;

  -- 3.2 UPDATE que mueve el check-in de la reserva del 14 al 16 hacia el 12 (se cruzaria con la del 9 al 14)
  SELECT id_reserva_habitacion INTO v_lin
    FROM reserva_habitacion
   WHERE id_habitacion = v_hab AND check_in = DATE '2027-01-14';

  BEGIN
    UPDATE reserva_habitacion SET check_in = DATE '2027-01-12' WHERE id_reserva_habitacion = v_lin;
    DBMS_OUTPUT.PUT_LINE('3.2 FALLÓ: el disparador permitió el solape');
  EXCEPTION
    WHEN pkg_reservas.e_solape_reserva THEN
      DBMS_OUTPUT.PUT_LINE('3.2 BLOQUEADO por el disparador: ' || SQLERRM);
  END;
END;
/

-- 3.3 Se deshacen las pruebas: no debe quedar ninguna reserva de enero de 2027
ROLLBACK;

SELECT COUNT(*) AS reservas_de_prueba_que_quedan
  FROM reserva
 WHERE check_in >= DATE '2027-01-01';


-- SECCION 4: Cursor de liquidacion mensual

-- 4.1 Liquidacion de diciembre de 2025 (temporada alta)
BEGIN
  pkg_reservas.sp_liquidacion_mensual(2025, 12);
END;
/

-- 4.2 Resultado guardado: una fila por alojamiento (60)
SELECT COUNT(*) AS alojamientos,
       SUM(reservas_completadas) AS reservas,
       SUM(total_liquidado) AS total_liquidado
  FROM liquidacion_mensual
 WHERE anio = 2025 AND mes = 12;

-- 4.3 Las mismas cifras con SQL directo (deben ser iguales a 4.2)
SELECT (SELECT COUNT(*)
          FROM reserva
         WHERE estado = 'COMPLETADA'
           AND check_in >= DATE '2025-12-01' AND check_in < DATE '2026-01-01') AS reservas_directo,
       (SELECT NVL(SUM(rh.valor_estadia), 0)
          FROM reserva_habitacion rh
          JOIN reserva r ON r.id_reserva = rh.id_reserva
         WHERE r.estado = 'COMPLETADA'
           AND r.check_in >= DATE '2025-12-01' AND r.check_in < DATE '2026-01-01')
     + (SELECT NVL(SUM(rs.cantidad * rs.precio_unitario), 0)
          FROM reserva_servicio rs
          JOIN reserva r ON r.id_reserva = rs.id_reserva
         WHERE r.estado = 'COMPLETADA'
           AND r.check_in >= DATE '2025-12-01' AND r.check_in < DATE '2026-01-01') AS total_directo
  FROM dual;

-- 4.4 Los 10 alojamientos con mayor liquidacion en diciembre de 2025
SELECT a.nombre_comercial AS alojamiento, mu.nombre AS municipio,
       l.reservas_completadas, l.ingreso_estadias, l.ingreso_servicios, l.total_liquidado
  FROM liquidacion_mensual l
  JOIN alojamiento a ON a.id_alojamiento = l.id_alojamiento
  JOIN municipio mu  ON mu.id_municipio = a.id_municipio
 WHERE l.anio = 2025 AND l.mes = 12
 ORDER BY l.total_liquidado DESC
 FETCH FIRST 10 ROWS ONLY;

-- 4.5 Otro mes con los mismos parametros del cursor, y un mes invalido
BEGIN
  pkg_reservas.sp_liquidacion_mensual(2026, 1);
END;
/

BEGIN
  pkg_reservas.sp_liquidacion_mensual(2025, 13);
EXCEPTION
  WHEN pkg_reservas.e_periodo_invalido THEN
    DBMS_OUTPUT.PUT_LINE('4.5 Error esperado: ' || SQLERRM);
END;
/

COMMIT;

SELECT anio, mes, COUNT(*) AS alojamientos, SUM(reservas_completadas) AS reservas,
       SUM(total_liquidado) AS total_liquidado
  FROM liquidacion_mensual
 GROUP BY anio, mes
 ORDER BY anio, mes;


-- SECCION 5: Paquete

-- 5.1 Subprogramas del paquete
SELECT object_name AS paquete, procedure_name AS subprograma
  FROM user_procedures
 WHERE object_name = 'PKG_RESERVAS'
   AND procedure_name IS NOT NULL
 ORDER BY procedure_name;

-- 5.2 Estado de los objetos de la Entrega 2 (todos VALID)
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name IN ('PKG_RESERVAS', 'TRG_TARIFA_AUDITORIA', 'TRG_RESHA_SOLAPE',
                       'MV_OCUPACION_MENSUAL')
 ORDER BY object_name, object_type;


-- SECCION 6: Disparador de sentencia, auditoria de TARIFA
-- Un UPDATE cambia tres tarifas (+10 %) y un DELETE borra otra; cada sentencia comparte usuario y fecha

DECLARE
  v_hab NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;

  UPDATE tarifa
     SET valor_noche = ROUND(valor_noche * 11 / 10, -3)
   WHERE id_habitacion = v_hab
     AND id_temporada IN (SELECT id_temporada
                            FROM temporada
                           WHERE nombre IN ('Semana Santa 2026', 'Mitad de año 2026',
                                            'Diciembre-enero 2026-2027'));
  DBMS_OUTPUT.PUT_LINE('6.1 Tarifas actualizadas con una sola sentencia: ' || SQL%ROWCOUNT);

  DELETE FROM tarifa
   WHERE id_habitacion = v_hab
     AND id_temporada = (SELECT id_temporada FROM temporada WHERE nombre = 'Puente de octubre 2026');
  DBMS_OUTPUT.PUT_LINE('6.2 Tarifas borradas con una sola sentencia: ' || SQL%ROWCOUNT);
END;
/

-- 6.3 Bitacora: tres filas UPDATE con valor anterior y nuevo, y una fila DELETE con valor nuevo nulo
SELECT id_auditoria,
       TO_CHAR(fecha_cambio, 'YYYY-MM-DD HH24:MI:SS') AS fecha,
       usuario, operacion, id_habitacion, id_temporada, valor_anterior, valor_nuevo
  FROM tarifa_auditoria
 ORDER BY id_auditoria;

-- 6.4 Se deshace la prueba: las tarifas y la auditoria vuelven a su estado (auditorias debe dar 0)
ROLLBACK;

SELECT COUNT(*) AS auditorias_tras_rollback FROM tarifa_auditoria;


-- SECCION 7: Historico de reservas en su tablespace

-- 7.1 RESERVA en USERS y RESERVA_HISTORICO en su tablespace
SELECT table_name, tablespace_name
  FROM user_tables
 WHERE table_name IN ('RESERVA', 'RESERVA_HISTORICO')
 ORDER BY table_name;

-- 7.2 Tabla e indice de llave primaria del historico
SELECT segment_name, segment_type, tablespace_name
  FROM user_segments
 WHERE segment_name IN ('RESERVA_HISTORICO', 'PK_RESERVA_HISTORICO')
 ORDER BY segment_name;

-- 7.3 Cuota sobre el tablespace (max_bytes = -1 es ilimitada)
SELECT tablespace_name, max_bytes
  FROM user_ts_quotas
 WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';

-- 7.4 Reservas archivadas contra las esperadas
SELECT (SELECT COUNT(*) FROM reserva_historico) AS en_historico,
       (SELECT COUNT(*)
          FROM reserva
         WHERE estado IN ('COMPLETADA', 'CANCELADA')
           AND check_out < DATE '2026-01-01') AS esperadas
  FROM dual;


-- SECCION 8: Vista materializada de ocupacion mensual

-- 8.1 La vista contra el calculo directo desde las tablas (filas_distintas debe ser 0)
SELECT COUNT(*) AS filas_distintas
  FROM (
    (SELECT id_alojamiento, anio, mes, noches_ocupadas, lineas_habitacion, reservas
       FROM mv_ocupacion_mensual
     MINUS
     SELECT rh.id_alojamiento,
            EXTRACT(YEAR FROM rh.check_in), EXTRACT(MONTH FROM rh.check_in),
            SUM(rh.check_out - rh.check_in), COUNT(*), COUNT(DISTINCT rh.id_reserva)
       FROM reserva_habitacion rh
       JOIN reserva r ON r.id_reserva = rh.id_reserva
      WHERE r.estado <> 'CANCELADA'
      GROUP BY rh.id_alojamiento, EXTRACT(YEAR FROM rh.check_in), EXTRACT(MONTH FROM rh.check_in))
    UNION ALL
    (SELECT rh.id_alojamiento,
            EXTRACT(YEAR FROM rh.check_in), EXTRACT(MONTH FROM rh.check_in),
            SUM(rh.check_out - rh.check_in), COUNT(*), COUNT(DISTINCT rh.id_reserva)
       FROM reserva_habitacion rh
       JOIN reserva r ON r.id_reserva = rh.id_reserva
      WHERE r.estado <> 'CANCELADA'
      GROUP BY rh.id_alojamiento, EXTRACT(YEAR FROM rh.check_in), EXTRACT(MONTH FROM rh.check_in)
     MINUS
     SELECT id_alojamiento, anio, mes, noches_ocupadas, lineas_habitacion, reservas
       FROM mv_ocupacion_mensual)
  );

-- 8.2 Porcentaje de ocupacion por municipio en enero, junio y diciembre de 2025
--     (noches ocupadas / (habitaciones del municipio x dias del mes))
SELECT mu.nombre AS municipio,
       mv.mes,
       SUM(mv.noches_ocupadas) AS noches_ocupadas,
       MAX(hm.habitaciones) AS habitaciones,
       ROUND(100 * SUM(mv.noches_ocupadas) /
             (MAX(hm.habitaciones) *
              EXTRACT(DAY FROM LAST_DAY(TO_DATE(mv.anio || '-' || LPAD(mv.mes, 2, '0') || '-01',
                                                'YYYY-MM-DD')))), 1) AS pct_ocupacion
  FROM mv_ocupacion_mensual mv
  JOIN alojamiento a ON a.id_alojamiento = mv.id_alojamiento
  JOIN municipio mu  ON mu.id_municipio = a.id_municipio
  JOIN (SELECT a2.id_municipio, COUNT(*) AS habitaciones
          FROM habitacion h2
          JOIN alojamiento a2 ON a2.id_alojamiento = h2.id_alojamiento
         GROUP BY a2.id_municipio) hm ON hm.id_municipio = a.id_municipio
 WHERE mv.anio = 2025
   AND mv.mes IN (1, 6, 12)
   AND mu.nombre IN ('Armenia', 'Salento', 'Córdoba')
 GROUP BY mu.nombre, mv.anio, mv.mes
 ORDER BY mu.nombre, mv.mes;

-- 8.3 Refresco manual y fecha del ultimo refresco
BEGIN
  DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
END;
/

SELECT mview_name, refresh_mode, refresh_method,
       TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') AS ultimo_refresco
  FROM user_mviews
 WHERE mview_name = 'MV_OCUPACION_MENSUAL';
