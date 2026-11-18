-- 11_indices.sql
-- Proyecto TurismoUQ · Bases de Datos II · Entrega 3 · Indices
-- Ejecutar como TURISMOUQ despues de 09_transacciones.sql
--
-- Tres consultas que hoy recorren la tabla completa, con su plan ANTES y DESPUES del indice
-- y una medicion de tiempo (cada consulta se repite muchas veces dentro de un bloque PL/SQL
-- para que la diferencia se pueda medir: una sola ejecucion tarda milisegundos).
--
--   Q1  Disponibilidad de una habitacion en un rango de fechas (la usa sp_crear_reserva
--       y el disparador de solapes)             -> indice COMPUESTO  idx_resha_hab_fechas
--   Q2  Pagos exitosos de un mes (cierre de caja)  -> indice BASADO EN FUNCION idx_pago_mes_fbi
--   Q3  Historial de reservas de un cliente (recepcion) -> indice B-tree sobre la FK idx_reserva_cliente
--   Q4  Caso donde el indice NO ayuda: reservas COMPLETADAS (70 % de la tabla) -> idx_reserva_estado
--
-- SECCION 0  Limpieza, estadisticas y tabla de mediciones
-- SECCION 1  Planes y tiempos ANTES
-- SECCION 2  Creacion de los indices
-- SECCION 3  Planes y tiempos DESPUES
-- SECCION 4  Caso donde el indice no ayuda
-- SECCION 5  Resumen

SET SERVEROUTPUT ON
SET DEFINE OFF
SET LINESIZE 200
SET PAGESIZE 200


-- SECCION 0: Limpieza, estadisticas y tabla de mediciones

-- se borran los indices de una corrida anterior para poder medir el ANTES
BEGIN
  FOR i IN (SELECT index_name
              FROM user_indexes
             WHERE index_name IN ('IDX_RESHA_HAB_FECHAS', 'IDX_PAGO_MES_FBI',
                                  'IDX_RESERVA_CLIENTE', 'IDX_RESERVA_ESTADO')) LOOP
    EXECUTE IMMEDIATE 'DROP INDEX ' || i.index_name;
  END LOOP;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE medicion_indice PURGE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE medicion_indice (
  consulta     VARCHAR2(10)  NOT NULL,
  momento      VARCHAR2(10)  NOT NULL,
  ejecuciones  NUMBER        NOT NULL,
  centesimas   NUMBER        NOT NULL,
  fecha        DATE          DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_medicion_indice PRIMARY KEY (consulta, momento),
  CONSTRAINT ck_medicion_momento CHECK (momento IN ('ANTES','DESPUES','FORZADO'))
);

COMMENT ON TABLE medicion_indice IS 'Tiempos de las consultas de la Entrega 3 antes y despues de crear los indices (centesimas de segundo).';

-- estadisticas frescas; histograma en RESERVA.ESTADO para que el optimizador conozca
-- que COMPLETADA es el 70 % de las filas y PENDIENTE apenas el 2 %
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA_HABITACION', cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGO', cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA', cascade => TRUE,
                                method_opt => 'FOR ALL COLUMNS SIZE 1 FOR COLUMNS estado SIZE 254');
END;
/

DELETE FROM plan_table WHERE statement_id LIKE 'Q%';
COMMIT;

-- Procedimiento de medicion: ejecuta la consulta pedida N veces con parametros distintos
-- y guarda el tiempo total. Usa SQL estatico: al crear un indice Oracle invalida los cursores
-- de la tabla y la siguiente ejecucion vuelve a optimizarse con el indice.
CREATE OR REPLACE PROCEDURE sp_medir_consulta (
  p_consulta IN VARCHAR2,
  p_momento  IN VARCHAR2
) IS
  v_ini     PLS_INTEGER;
  v_n       PLS_INTEGER;
  v_min_hab NUMBER;
  v_min_cli NUMBER;
  v_cnt     NUMBER;
  v_sum     NUMBER;
  v_fecha   DATE;
BEGIN
  SELECT MIN(id_habitacion) INTO v_min_hab FROM habitacion;
  SELECT MIN(id_cliente)    INTO v_min_cli FROM cliente;
  v_ini := DBMS_UTILITY.GET_TIME;

  IF p_consulta = 'Q1' THEN
    v_n := 3000;
    FOR i IN 1 .. v_n LOOP
      SELECT COUNT(*) INTO v_cnt
        FROM reserva_habitacion
       WHERE id_habitacion = v_min_hab + MOD(i, 650)
         AND check_in  < DATE '2025-12-26'
         AND check_out > DATE '2025-12-20';
    END LOOP;

  ELSIF p_consulta = 'Q2' THEN
    v_n := 1000;
    FOR i IN 1 .. v_n LOOP
      SELECT COUNT(*), NVL(SUM(monto), 0) INTO v_cnt, v_sum
        FROM pago
       WHERE TRUNC(fecha_pago, 'MM') = ADD_MONTHS(DATE '2024-01-01', MOD(i, 33))
         AND estado = 'EXITOSO';
    END LOOP;

  ELSIF p_consulta = 'Q3' THEN
    v_n := 3000;
    FOR i IN 1 .. v_n LOOP
      SELECT COUNT(*), MAX(check_in) INTO v_cnt, v_fecha
        FROM reserva r
       WHERE r.id_cliente = v_min_cli + MOD(i, 3000);
    END LOOP;

  ELSIF p_consulta = 'Q4' AND p_momento = 'FORZADO' THEN
    v_n := 300;
    FOR i IN 1 .. v_n LOOP
      SELECT /*+ INDEX(r idx_reserva_estado) */ COUNT(DISTINCT id_alojamiento), SUM(check_out - check_in)
        INTO v_cnt, v_sum
        FROM reserva r
       WHERE estado = 'COMPLETADA';
    END LOOP;

  ELSIF p_consulta = 'Q4' THEN
    v_n := 300;
    FOR i IN 1 .. v_n LOOP
      SELECT COUNT(DISTINCT id_alojamiento), SUM(check_out - check_in)
        INTO v_cnt, v_sum
        FROM reserva r
       WHERE estado = 'COMPLETADA';
    END LOOP;
  END IF;

  INSERT INTO medicion_indice (consulta, momento, ejecuciones, centesimas)
  VALUES (p_consulta, p_momento, v_n, DBMS_UTILITY.GET_TIME - v_ini);
  COMMIT;

  DBMS_OUTPUT.PUT_LINE(p_consulta || ' ' || RPAD(p_momento, 8) || ': ' || v_n || ' ejecuciones en ' ||
                       TO_CHAR((DBMS_UTILITY.GET_TIME - v_ini) / 100, 'FM990.00') || ' s');
END sp_medir_consulta;
/


-- SECCION 1: Planes y tiempos ANTES de los indices

-- Q1 Disponibilidad: ¿la habitacion tiene alguna linea de reserva que se cruce con el 20-26 de diciembre?
EXPLAIN PLAN SET STATEMENT_ID = 'Q1_ANTES' FOR
SELECT COUNT(*)
  FROM reserva_habitacion
 WHERE id_habitacion = 700
   AND check_in  < DATE '2025-12-26'
   AND check_out > DATE '2025-12-20';

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q1_ANTES', 'BASIC +ROWS +COST +PREDICATE'));

-- Q2 Cierre de caja: total de pagos exitosos de diciembre de 2025.
-- TRUNC(fecha_pago,'MM') sobre la columna impide usar un indice normal sobre fecha_pago
EXPLAIN PLAN SET STATEMENT_ID = 'Q2_ANTES' FOR
SELECT COUNT(*), SUM(monto)
  FROM pago
 WHERE TRUNC(fecha_pago, 'MM') = DATE '2025-12-01'
   AND estado = 'EXITOSO';

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q2_ANTES', 'BASIC +ROWS +COST +PREDICATE'));

-- Q3 Historial de un cliente (lo que consulta recepcion cuando el cliente llega)
EXPLAIN PLAN SET STATEMENT_ID = 'Q3_ANTES' FOR
SELECT r.id_reserva, r.check_in, r.check_out, r.estado, a.nombre_comercial
  FROM reserva r
  JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
 WHERE r.id_cliente = 3050
 ORDER BY r.check_in DESC;

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q3_ANTES', 'BASIC +ROWS +COST +PREDICATE'));

-- Tiempos antes
EXEC sp_medir_consulta('Q1', 'ANTES')
EXEC sp_medir_consulta('Q2', 'ANTES')
EXEC sp_medir_consulta('Q3', 'ANTES')


-- SECCION 2: Creacion de los indices

-- Compuesto: primero la columna de igualdad (id_habitacion) y luego las de rango (check_in, check_out).
-- Con check_out dentro del indice Oracle resuelve todo el filtro sin ir a la tabla.
CREATE INDEX idx_resha_hab_fechas ON reserva_habitacion (id_habitacion, check_in, check_out);

-- Basado en funcion: indexa el valor ya truncado al mes, que es exactamente la expresion del WHERE.
-- Incluye estado y monto para que la consulta se responda solo con el indice (indice de cobertura).
CREATE INDEX idx_pago_mes_fbi ON pago (TRUNC(fecha_pago, 'MM'), estado, monto);

-- B-tree sobre la llave foranea RESERVA.id_cliente (ademas evita bloqueos de tabla en CLIENTE
-- cuando se borra o actualiza un cliente)
CREATE INDEX idx_reserva_cliente ON reserva (id_cliente);

-- estadisticas del indice basado en funcion (columna virtual oculta)
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGO', cascade => TRUE,
                                method_opt => 'FOR ALL HIDDEN COLUMNS SIZE AUTO');
END;
/

SELECT index_name, table_name, index_type, uniqueness
  FROM user_indexes
 WHERE index_name IN ('IDX_RESHA_HAB_FECHAS', 'IDX_PAGO_MES_FBI', 'IDX_RESERVA_CLIENTE')
 ORDER BY index_name;

SELECT index_name, column_position, column_name
  FROM user_ind_columns
 WHERE index_name IN ('IDX_RESHA_HAB_FECHAS', 'IDX_PAGO_MES_FBI', 'IDX_RESERVA_CLIENTE')
 ORDER BY index_name, column_position;

-- la expresion del indice basado en funcion
SELECT index_name, column_expression
  FROM user_ind_expressions
 WHERE index_name = 'IDX_PAGO_MES_FBI';


-- SECCION 3: Planes y tiempos DESPUES de los indices

EXPLAIN PLAN SET STATEMENT_ID = 'Q1_DESPUES' FOR
SELECT COUNT(*)
  FROM reserva_habitacion
 WHERE id_habitacion = 700
   AND check_in  < DATE '2025-12-26'
   AND check_out > DATE '2025-12-20';

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q1_DESPUES', 'BASIC +ROWS +COST +PREDICATE'));

EXPLAIN PLAN SET STATEMENT_ID = 'Q2_DESPUES' FOR
SELECT COUNT(*), SUM(monto)
  FROM pago
 WHERE TRUNC(fecha_pago, 'MM') = DATE '2025-12-01'
   AND estado = 'EXITOSO';

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q2_DESPUES', 'BASIC +ROWS +COST +PREDICATE'));

EXPLAIN PLAN SET STATEMENT_ID = 'Q3_DESPUES' FOR
SELECT r.id_reserva, r.check_in, r.check_out, r.estado, a.nombre_comercial
  FROM reserva r
  JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
 WHERE r.id_cliente = 3050
 ORDER BY r.check_in DESC;

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q3_DESPUES', 'BASIC +ROWS +COST +PREDICATE'));

-- Tiempos despues
EXEC sp_medir_consulta('Q1', 'DESPUES')
EXEC sp_medir_consulta('Q2', 'DESPUES')
EXEC sp_medir_consulta('Q3', 'DESPUES')


-- SECCION 4: Caso donde el indice NO ayuda
-- Indice sobre RESERVA.estado y consulta de las reservas COMPLETADAS.
-- Por que no ayuda:
--  * baja selectividad: estado solo tiene 4 valores y COMPLETADA es cerca del 70 % de las filas;
--  * con el indice Oracle tendria que leer la hoja del indice y luego ir a la tabla fila por fila
--    (TABLE ACCESS BY INDEX ROWID), visitando casi todos los bloques de la tabla, muchos varias veces
--    porque las filas COMPLETADAS estan repartidas por toda la tabla (factor de agrupamiento alto);
--  * un TABLE ACCESS FULL lee esos mismos bloques una sola vez y en lecturas multibloque.
-- Por eso el optimizador lo ignora. Si se le obliga con un hint, el costo y el tiempo suben.
-- El mismo indice SI se usa para PENDIENTE (2 % de las filas): lo que decide es la selectividad.

CREATE INDEX idx_reserva_estado ON reserva (estado);

BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA', cascade => TRUE,
                                method_opt => 'FOR ALL COLUMNS SIZE 1 FOR COLUMNS estado SIZE 254');
END;
/

-- distribucion de estados (la razon tecnica)
SELECT estado, COUNT(*) AS reservas,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS pct
  FROM reserva
 GROUP BY estado
 ORDER BY reservas DESC;

-- 4.1 Plan natural: el optimizador NO usa el indice (TABLE ACCESS FULL)
EXPLAIN PLAN SET STATEMENT_ID = 'Q4_NATURAL' FOR
SELECT COUNT(DISTINCT id_alojamiento), SUM(check_out - check_in)
  FROM reserva r
 WHERE estado = 'COMPLETADA';

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q4_NATURAL', 'BASIC +ROWS +COST +PREDICATE'));

-- 4.2 Plan forzado con hint: usa el indice y el costo sube
EXPLAIN PLAN SET STATEMENT_ID = 'Q4_FORZADO' FOR
SELECT /*+ INDEX(r idx_reserva_estado) */ COUNT(DISTINCT id_alojamiento), SUM(check_out - check_in)
  FROM reserva r
 WHERE estado = 'COMPLETADA';

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q4_FORZADO', 'BASIC +ROWS +COST +PREDICATE'));

-- 4.3 Contraste: con un valor selectivo (PENDIENTE) el mismo indice si se usa
EXPLAIN PLAN SET STATEMENT_ID = 'Q4_PENDIENTE' FOR
SELECT COUNT(DISTINCT id_alojamiento), SUM(check_out - check_in)
  FROM reserva r
 WHERE estado = 'PENDIENTE';

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q4_PENDIENTE', 'BASIC +ROWS +COST +PREDICATE'));

-- 4.4 Tiempos: plan natural (sin indice) contra plan forzado (con indice)
EXEC sp_medir_consulta('Q4', 'ANTES')
EXEC sp_medir_consulta('Q4', 'FORZADO')


-- SECCION 5: Resumen

-- costo del optimizador (fila id = 0 de cada plan)
SELECT statement_id AS plan, cost AS costo, cardinality AS filas_estimadas
  FROM plan_table
 WHERE id = 0
   AND statement_id LIKE 'Q%'
 ORDER BY statement_id;

-- tiempos medidos (ANTES = sin indice / plan natural; DESPUES = con indice; FORZADO = indice por hint)
SELECT consulta, ejecuciones,
       MAX(CASE WHEN momento = 'ANTES'   THEN centesimas END) / 100 AS seg_antes,
       MAX(CASE WHEN momento = 'DESPUES' THEN centesimas END) / 100 AS seg_despues,
       MAX(CASE WHEN momento = 'FORZADO' THEN centesimas END) / 100 AS seg_forzado
  FROM medicion_indice
 GROUP BY consulta, ejecuciones
 ORDER BY consulta;


-- SECCION 6: Vista materializada
-- Crear indices y confirmar cambios en RESERVA y RESERVA_HABITACION deja MV_OCUPACION_MENSUAL
-- en estado NEEDS_COMPILE / INVALID. Se refresca (COMPLETE ON DEMAND) para dejarla VALID y al dia.
BEGIN
  DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
END;
/

SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name = 'MV_OCUPACION_MENSUAL';
