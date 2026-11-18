-- 10_concurrencia.sql
-- Proyecto TurismoUQ · Bases de Datos II · Entrega 3 · Concurrencia
-- Ejecutar como TURISMOUQ despues de 09_transacciones.sql
--
-- Experimento: dos sesiones intentan reservar la MISMA habitacion para fechas que se cruzan.
-- Este script NO se ejecuta completo con F5. Abrirlo en dos hojas de trabajo NO compartidas de
-- SQL Developer (clic derecho en la conexion > "Abrir hoja de trabajo SQL no compartida", o
-- Ctrl+Shift+N), una para la Sesion A y otra para la Sesion B, y ejecutar cada paso en su hoja,
-- en el orden del tiempo T1, T2, T3... (seleccionar el bloque y F5). NO usar autocommit.
--
--  PARTE 1 · Sin FOR UPDATE (pkg_reservas.sp_crear_reserva)
--    T1  A reserva la habitacion del 5 al 8 de enero de 2027 (no confirma)
--    T2  B reserva la misma habitacion del 6 al 9 de enero (no confirma) -> NO se bloquea:
--        B no ve la fila sin confirmar de A, su revision de disponibilidad da 0
--    T3  A hace COMMIT
--    T4  B hace COMMIT -> quedan DOS reservas cruzadas: sobreventa
--    T5  A revisa el resultado y limpia
--
--  PARTE 2 · Con SELECT ... FOR UPDATE (pkg_transacciones.sp_reservar_con_bloqueo)
--    T6  A reserva la habitacion del 5 al 8 de enero (bloquea la fila de HABITACION, no confirma)
--    T7  B pide la misma habitacion del 6 al 9 -> queda ESPERANDO (bloqueo real)
--        (opcional, desde SYSTEM: consulta de V$SESSION al final de este archivo)
--    T8  A hace COMMIT -> B despierta, ahora si ve la reserva de A y recibe ORA-20002
--    T9  A revisa el resultado y limpia

-- En las dos hojas (Sesion A y Sesion B)
SET SERVEROUTPUT ON
SET DEFINE OFF
SET TIMING ON

-- Habitacion del experimento: la de menor id. Clientes: el de menor id (A) y el siguiente (B)
SELECT MIN(id_habitacion) AS habitacion_experimento FROM habitacion;


-- =====================  PARTE 1: SIN FOR UPDATE  =====================

-- T1 (Sesion A)
DECLARE
  v_hab NUMBER;
  v_cli NUMBER;
  v_res NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
  SELECT MIN(id_cliente) INTO v_cli FROM cliente;
  pkg_reservas.sp_crear_reserva(v_cli, v_hab, DATE '2027-01-05', DATE '2027-01-08', 1, v_res);
  DBMS_OUTPUT.PUT_LINE('T1 A ' || TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') ||
                       ' -> reserva ' || v_res || ' creada (sin COMMIT)');
END;
/

-- T2 (Sesion B): termina enseguida y crea la reserva, aunque A ya tomo esas noches
DECLARE
  v_hab NUMBER;
  v_cli NUMBER;
  v_res NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
  SELECT MIN(id_cliente) + 1 INTO v_cli FROM cliente;
  pkg_reservas.sp_crear_reserva(v_cli, v_hab, DATE '2027-01-06', DATE '2027-01-09', 1, v_res);
  DBMS_OUTPUT.PUT_LINE('T2 B ' || TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') ||
                       ' -> reserva ' || v_res || ' creada (sin COMMIT): B no ve la reserva de A');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T2 B ' || TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') || ' -> RECHAZADA: ' || SQLERRM);
END;
/

-- T3 (Sesion A)
COMMIT;

-- T4 (Sesion B)
COMMIT;

-- T5 (Sesion A): dos reservas confirmadas que se cruzan en la misma habitacion
SELECT r.id_reserva, r.id_cliente, rh.id_habitacion, rh.check_in, rh.check_out, r.estado
  FROM reserva r
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
 WHERE rh.id_habitacion = (SELECT MIN(id_habitacion) FROM habitacion)
   AND rh.check_in >= DATE '2027-01-01' AND rh.check_in < DATE '2027-01-15'
 ORDER BY r.id_reserva;

-- limpieza de la parte 1 (Sesion A)
DELETE FROM reserva_habitacion
 WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE check_in >= DATE '2027-01-01' AND check_in < DATE '2027-01-15');
DELETE FROM reserva WHERE check_in >= DATE '2027-01-01' AND check_in < DATE '2027-01-15';
COMMIT;


-- =====================  PARTE 2: CON SELECT ... FOR UPDATE  =====================

-- T6 (Sesion A)
DECLARE
  v_hab NUMBER;
  v_cli NUMBER;
  v_res NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
  SELECT MIN(id_cliente) INTO v_cli FROM cliente;
  pkg_transacciones.sp_reservar_con_bloqueo(v_cli, v_hab, DATE '2027-01-05', DATE '2027-01-08', 1, v_res);
  DBMS_OUTPUT.PUT_LINE('T6 A ' || TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') ||
                       ' -> reserva ' || v_res || ' creada con FOR UPDATE (sin COMMIT)');
END;
/

-- T7 (Sesion B): se queda esperando en el FOR UPDATE hasta que A haga COMMIT (T8).
-- Cuando A confirma, B continua, revisa la disponibilidad y ya ve la reserva de A.
DECLARE
  v_hab NUMBER;
  v_cli NUMBER;
  v_res NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
  SELECT MIN(id_cliente) + 1 INTO v_cli FROM cliente;
  DBMS_OUTPUT.PUT_LINE('T7 B ' || TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') || ' -> pide la habitación');
  pkg_transacciones.sp_reservar_con_bloqueo(v_cli, v_hab, DATE '2027-01-06', DATE '2027-01-09', 1, v_res);
  DBMS_OUTPUT.PUT_LINE('T8 B ' || TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') || ' -> reserva ' || v_res || ' creada');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T8 B ' || TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') || ' -> RECHAZADA: ' || SQLERRM);
    ROLLBACK;
END;
/

-- T8 (Sesion A): esperar unos segundos mirando que B no termina; al confirmar se libera el bloqueo
COMMIT;

-- T9 (Sesion A): solo existe la reserva de A
SELECT r.id_reserva, r.id_cliente, rh.id_habitacion, rh.check_in, rh.check_out, r.estado
  FROM reserva r
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
 WHERE rh.id_habitacion = (SELECT MIN(id_habitacion) FROM habitacion)
   AND rh.check_in >= DATE '2027-01-01' AND rh.check_in < DATE '2027-01-15'
 ORDER BY r.id_reserva;

-- limpieza de la parte 2 (Sesion A)
DELETE FROM reserva_habitacion
 WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE check_in >= DATE '2027-01-01' AND check_in < DATE '2027-01-15');
DELETE FROM reserva WHERE check_in >= DATE '2027-01-01' AND check_in < DATE '2027-01-15';
COMMIT;


-- (Opcional) Ver el bloqueo desde una tercera conexion como SYSTEM mientras B espera en T7:
-- SELECT sid, serial#, username, status, blocking_session, event, seconds_in_wait
--   FROM v$session
--  WHERE username = 'TURISMOUQ';
-- La sesion B aparece con BLOCKING_SESSION = SID de A y EVENT = 'enq: TX - row lock contention'.
