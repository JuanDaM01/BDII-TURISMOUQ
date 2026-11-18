-- 14_pruebas.sql
-- Proyecto TurismoUQ · Bases de Datos II · Entrega 3 · Pruebas de seguridad
-- Ejecutar con F5 (Run Script) en SQL Developer despues de 13_seguridad.sql.
-- El script se conecta como cada usuario de prueba con CONNECT. Si su servicio no es XEPDB1
-- (por ejemplo FREEPDB1) cambie la cadena de conexion en cada CONNECT.
-- Los errores ORA-00942 y ORA-01031 que aparecen son ESPERADOS: son la evidencia de que
-- cada rol solo puede hacer lo que le corresponde.

SET SERVEROUTPUT ON
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE


-- =====================  1. RECEPCION  =====================
CONNECT uq_recepcion/"Recepcion_2026"@//localhost:1521/XEPDB1

-- 1.1 Lo que tiene: las vistas (funciona)
SELECT COUNT(*) AS habitaciones_visibles FROM turismouq.v_rec_habitaciones;

SELECT id_reserva, cliente, alojamiento, check_in, check_out, estado, valor_total, pagado
  FROM turismouq.v_rec_reservas
 ORDER BY check_in
 FETCH FIRST 5 ROWS ONLY;

-- 1.2 Consultar una TABLA directamente: ORA-00942 (Oracle ni siquiera revela que la tabla existe)
SELECT * FROM turismouq.reserva WHERE ROWNUM <= 5;

SELECT * FROM turismouq.cliente WHERE ROWNUM <= 5;

-- 1.3 Modificar una vista de solo lectura sobre la que solo tiene SELECT: ORA-01031
UPDATE turismouq.v_rec_reservas SET estado = 'CANCELADA' WHERE ROWNUM = 1;

-- 1.4 Corregir el telefono de un cliente por la vista (permitido) y deshacer
UPDATE turismouq.v_rec_clientes
   SET telefono = '3000000000'
 WHERE id_cliente = (SELECT MIN(id_cliente) FROM turismouq.v_rec_clientes);
ROLLBACK;

-- 1.5 Pero no puede cambiar el nombre (el UPDATE solo se otorgo sobre correo y telefono): ORA-01031
UPDATE turismouq.v_rec_clientes
   SET nombre = 'Otro nombre'
 WHERE id_cliente = (SELECT MIN(id_cliente) FROM turismouq.v_rec_clientes);

-- 1.6 Registrar una reserva con pago: solo a traves del procedimiento (sin tocar tablas)
DECLARE
  v_hab  NUMBER;
  v_cli  NUMBER;
  v_res  NUMBER;
  v_pago NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM turismouq.v_rec_habitaciones;
  SELECT MIN(id_cliente)    INTO v_cli FROM turismouq.v_rec_clientes;
  turismouq.pkg_transacciones.sp_reserva_con_pago(v_cli, v_hab, DATE '2027-01-20', DATE '2027-01-22', 1,
                                                  100000, 'EFECTIVO', NULL, 1, v_res, v_pago);
  DBMS_OUTPUT.PUT_LINE('1.6 Recepción registró la reserva ' || v_res || ' con el pago ' || v_pago);
END;
/


-- =====================  2. ADMINISTRADOR DE ALOJAMIENTO  =====================
CONNECT uq_admin_aloj/"AdminAloj_2026"@//localhost:1521/XEPDB1

-- 2.1 Sube una tarifa (permitido). El disparador de auditoria registra al usuario UQ_ADMIN_ALOJ
UPDATE turismouq.tarifa
   SET valor_noche = valor_noche + 10000
 WHERE id_tarifa = (SELECT MIN(id_tarifa) FROM turismouq.tarifa);
COMMIT;

-- y la devuelve a su valor (queda un segundo registro de auditoria)
UPDATE turismouq.tarifa
   SET valor_noche = valor_noche - 10000
 WHERE id_tarifa = (SELECT MIN(id_tarifa) FROM turismouq.tarifa);
COMMIT;

-- 2.2 No puede borrar pagos (solo tiene SELECT): ORA-01031
DELETE FROM turismouq.pago WHERE ROWNUM = 1;

-- 2.3 No ve la auditoria (no tiene ningun privilegio sobre ella): ORA-00942
SELECT * FROM turismouq.tarifa_auditoria;


-- =====================  3. GERENTE  =====================
CONNECT uq_gerente/"Gerente_2026"@//localhost:1521/XEPDB1

-- 3.1 Lectura para analisis (permitido): ingresos de 2025 por tipo de alojamiento
SELECT ta.nombre AS tipo_alojamiento, SUM(rh.valor_estadia) AS ingresos_2025
  FROM turismouq.reserva_habitacion rh
  JOIN turismouq.reserva r           ON r.id_reserva = rh.id_reserva
  JOIN turismouq.alojamiento a       ON a.id_alojamiento = rh.id_alojamiento
  JOIN turismouq.tipo_alojamiento ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
 WHERE r.estado = 'COMPLETADA'
   AND rh.check_in >= DATE '2025-01-01' AND rh.check_in < DATE '2026-01-01'
 GROUP BY ta.nombre
 ORDER BY ingresos_2025 DESC;

-- 3.2 No puede modificar tarifas: ORA-01031
UPDATE turismouq.tarifa SET valor_noche = 1 WHERE ROWNUM = 1;


-- =====================  4. AUDITOR  =====================
CONNECT uq_auditor/"Auditor_2026"@//localhost:1521/XEPDB1

-- 4.1 Lee la auditoria (permitido): aparecen los dos cambios hechos por UQ_ADMIN_ALOJ
SELECT id_auditoria, TO_CHAR(fecha_cambio, 'YYYY-MM-DD HH24:MI:SS') AS fecha,
       usuario, operacion, id_tarifa, valor_anterior, valor_nuevo
  FROM turismouq.tarifa_auditoria
 ORDER BY id_auditoria DESC
 FETCH FIRST 5 ROWS ONLY;

-- 4.2 No puede borrar la auditoria: ORA-01031
DELETE FROM turismouq.tarifa_auditoria;

-- 4.3 No puede ver clientes (no son parte de su trabajo): ORA-00942
SELECT * FROM turismouq.cliente WHERE ROWNUM <= 5;


-- =====================  5. PERFIL: FAILED_LOGIN_ATTEMPTS = 3  =====================
-- Tres claves equivocadas (ORA-01017) y al cuarto intento, aun con la clave correcta,
-- la cuenta esta bloqueada (ORA-28000). El bloqueo dura 1 minuto (PASSWORD_LOCK_TIME 1/1440).
CONNECT uq_gerente/"clave_mala"@//localhost:1521/XEPDB1
CONNECT uq_gerente/"clave_mala"@//localhost:1521/XEPDB1
CONNECT uq_gerente/"clave_mala"@//localhost:1521/XEPDB1
CONNECT uq_gerente/"Gerente_2026"@//localhost:1521/XEPDB1

-- SESSIONS_PER_USER = 2: abrir tres conexiones como uq_recepcion en SQL Developer;
-- la tercera recibe ORA-02391: se ha excedido el límite simultáneo SESSIONS_PER_USER.
-- IDLE_TIME = 10: dejar una sesion quieta 10 minutos; la siguiente sentencia recibe ORA-02396.


-- =====================  6. LIMPIEZA (como dueño del esquema)  =====================
CONNECT turismouq/"TurismoUQ_2026"@//localhost:1521/XEPDB1

-- se borra la reserva que creo recepcion en 1.6
DELETE FROM pago               WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE check_in >= DATE '2027-01-20' AND check_in < DATE '2027-02-01');
DELETE FROM reserva_habitacion WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE check_in >= DATE '2027-01-20' AND check_in < DATE '2027-02-01');
DELETE FROM reserva            WHERE check_in >= DATE '2027-01-20' AND check_in < DATE '2027-02-01';
COMMIT;

-- la tarifa quedo con su valor original (las dos filas de auditoria muestran la subida y la bajada)
SELECT usuario, operacion, valor_anterior, valor_nuevo
  FROM tarifa_auditoria
 WHERE usuario = 'UQ_ADMIN_ALOJ'
 ORDER BY id_auditoria;

-- la reserva de prueba y su borrado tocaron RESERVA y RESERVA_HABITACION: la vista materializada
-- (COMPLETE ON DEMAND) queda desactualizada (NEEDS_COMPILE) hasta que se refresca
BEGIN
  DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
END;
/
