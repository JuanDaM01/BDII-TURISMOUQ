-- 09_transacciones.sql
-- Proyecto TurismoUQ · Bases de Datos II · Entrega 3
-- Ejecutar como TURISMOUQ despues de 04_paquete_reservas.sql y 05_disparadores.sql
--
-- Contenido:
--   SECCION 1  Paquete PKG_TRANSACCIONES
--              * sp_reserva_con_pago: registra reserva + pago (y un servicio opcional) en una sola
--                transaccion. Reserva y pago son atomicos: si el pago falla se deshace todo.
--                El servicio es opcional: si falla se deshace solo el servicio (rollback parcial).
--              * sp_reservar_con_bloqueo: igual que sp_crear_reserva pero bloquea la habitacion
--                con SELECT ... FOR UPDATE antes de revisar la disponibilidad (ver 10_concurrencia).
--   SECCION 2  Verificacion de compilacion
--   SECCION 3  Demostracion paso a paso de un rollback parcial con SAVEPOINT (sin procedimiento)
--   SECCION 4  Pruebas del procedimiento: caso valido, servicio descartado y pago rechazado
--
-- Las pruebas usan enero de 2027 (fechas que la carga deja libres) y al final borran lo que crearon.

SET SERVEROUTPUT ON
SET DEFINE OFF


-- SECCION 1: Paquete PKG_TRANSACCIONES

CREATE OR REPLACE PACKAGE pkg_transacciones AS

  e_pago_invalido      EXCEPTION;
  e_servicio_invalido  EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_pago_invalido,     -20011);  -- monto o metodo de pago no valido
  PRAGMA EXCEPTION_INIT(e_servicio_invalido, -20012);  -- el servicio no existe o es de otro alojamiento

  -- Reserva + pago en una sola transaccion. Termina con COMMIT si todo sale bien.
  PROCEDURE sp_reserva_con_pago (
    p_id_cliente     IN  NUMBER,
    p_id_habitacion  IN  NUMBER,
    p_check_in       IN  DATE,
    p_check_out      IN  DATE,
    p_huespedes      IN  NUMBER,
    p_monto_pago     IN  NUMBER,
    p_metodo_pago    IN  VARCHAR2,
    p_id_servicio    IN  NUMBER DEFAULT NULL,
    p_cant_servicio  IN  NUMBER DEFAULT 1,
    p_id_reserva     OUT NUMBER,
    p_id_pago        OUT NUMBER
  );

  -- Reserva con bloqueo pesimista de la habitacion. NO hace COMMIT: lo decide quien la llama,
  -- asi el bloqueo se mantiene hasta el final de la transaccion.
  PROCEDURE sp_reservar_con_bloqueo (
    p_id_cliente     IN  NUMBER,
    p_id_habitacion  IN  NUMBER,
    p_check_in       IN  DATE,
    p_check_out      IN  DATE,
    p_huespedes      IN  NUMBER,
    p_id_reserva     OUT NUMBER
  );

END pkg_transacciones;
/

CREATE OR REPLACE PACKAGE BODY pkg_transacciones AS

  PROCEDURE sp_reserva_con_pago (
    p_id_cliente     IN  NUMBER,
    p_id_habitacion  IN  NUMBER,
    p_check_in       IN  DATE,
    p_check_out      IN  DATE,
    p_huespedes      IN  NUMBER,
    p_monto_pago     IN  NUMBER,
    p_metodo_pago    IN  VARCHAR2,
    p_id_servicio    IN  NUMBER DEFAULT NULL,
    p_cant_servicio  IN  NUMBER DEFAULT 1,
    p_id_reserva     OUT NUMBER,
    p_id_pago        OUT NUMBER
  ) IS
    v_id_aloj    reserva.id_alojamiento%TYPE;
    v_estadia    NUMBER;
    v_servicios  NUMBER;
  BEGIN
    -- Punto de partida: si algo grave falla se vuelve aqui y no queda nada de esta operacion
    SAVEPOINT sp_inicio;

    -- 1. Reserva: reutiliza las validaciones de la Entrega 2 (fechas, cliente, capacidad, disponibilidad)
    pkg_reservas.sp_crear_reserva(p_id_cliente, p_id_habitacion, p_check_in, p_check_out,
                                  p_huespedes, p_id_reserva);

    SELECT r.id_alojamiento, rh.valor_estadia
      INTO v_id_aloj, v_estadia
      FROM reserva r
      JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
     WHERE r.id_reserva = p_id_reserva;

    -- La reserva ya esta escrita: este savepoint separa lo obligatorio de lo opcional
    SAVEPOINT sp_reserva_creada;

    -- 2. Servicio opcional: si falla se deshace solo el servicio y la operacion sigue
    IF p_id_servicio IS NOT NULL THEN
      BEGIN
        INSERT INTO reserva_servicio (id_reserva, id_servicio, id_alojamiento, cantidad, precio_unitario)
        SELECT p_id_reserva, s.id_servicio, s.id_alojamiento, p_cant_servicio, s.precio
          FROM servicio s
         WHERE s.id_servicio = p_id_servicio
           AND s.id_alojamiento = v_id_aloj;

        IF SQL%ROWCOUNT = 0 THEN
          RAISE_APPLICATION_ERROR(-20012, 'El servicio ' || p_id_servicio ||
                                  ' no existe o no pertenece al alojamiento ' || v_id_aloj || '.');
        END IF;
      EXCEPTION
        WHEN OTHERS THEN
          ROLLBACK TO sp_reserva_creada;   -- rollback parcial: la reserva sigue en pie
          DBMS_OUTPUT.PUT_LINE('Servicio descartado (ROLLBACK TO sp_reserva_creada): ' || SQLERRM);
      END;
    END IF;

    -- 3. Pago: es obligatorio. Debe ser positivo y no superar el total de la reserva
    SELECT NVL(SUM(cantidad * precio_unitario), 0)
      INTO v_servicios
      FROM reserva_servicio
     WHERE id_reserva = p_id_reserva;

    IF p_monto_pago IS NULL OR p_monto_pago <= 0 OR p_monto_pago > v_estadia + v_servicios THEN
      RAISE_APPLICATION_ERROR(-20011, 'Pago inválido: el monto debe ser mayor que 0 y no superar ' ||
                              (v_estadia + v_servicios) || ' (estadía + servicios).');
    END IF;
    IF p_metodo_pago IS NULL OR p_metodo_pago NOT IN ('TARJETA_CREDITO','TARJETA_DEBITO',
                                                      'PSE','TRANSFERENCIA','EFECTIVO') THEN
      RAISE_APPLICATION_ERROR(-20011, 'Pago inválido: método ' || NVL(p_metodo_pago, 'NULL') ||
                              ' no permitido.');
    END IF;

    INSERT INTO pago (id_reserva, fecha_pago, monto, metodo, estado)
    VALUES (p_id_reserva, TRUNC(SYSDATE), p_monto_pago, p_metodo_pago, 'EXITOSO')
    RETURNING id_pago INTO p_id_pago;

    -- Con un pago exitoso la reserva queda confirmada
    UPDATE reserva SET estado = 'CONFIRMADA' WHERE id_reserva = p_id_reserva;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Reserva ' || p_id_reserva || ' confirmada con el pago ' || p_id_pago ||
                         ' por ' || p_monto_pago || ' de un total de ' || (v_estadia + v_servicios) || '.');
  EXCEPTION
    WHEN OTHERS THEN
      -- Atomicidad: reserva y pago van juntos o no va ninguno
      ROLLBACK TO sp_inicio;
      p_id_reserva := NULL;
      p_id_pago    := NULL;
      RAISE;
  END sp_reserva_con_pago;


  PROCEDURE sp_reservar_con_bloqueo (
    p_id_cliente     IN  NUMBER,
    p_id_habitacion  IN  NUMBER,
    p_check_in       IN  DATE,
    p_check_out      IN  DATE,
    p_huespedes      IN  NUMBER,
    p_id_reserva     OUT NUMBER
  ) IS
    v_hab habitacion.id_habitacion%TYPE;
  BEGIN
    -- Bloqueo de la fila de la habitacion: una segunda sesion que pida la misma habitacion
    -- se queda esperando aqui hasta que la primera haga COMMIT o ROLLBACK. Cuando sigue,
    -- la revision de disponibilidad ya ve la reserva confirmada por la primera.
    BEGIN
      SELECT id_habitacion
        INTO v_hab
        FROM habitacion
       WHERE id_habitacion = p_id_habitacion
         FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20004, 'La habitación ' || p_id_habitacion || ' no existe.');
    END;

    pkg_reservas.sp_crear_reserva(p_id_cliente, p_id_habitacion, p_check_in, p_check_out,
                                  p_huespedes, p_id_reserva);
  END sp_reservar_con_bloqueo;

END pkg_transacciones;
/


-- SECCION 2: Verificacion de compilacion

SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name = 'PKG_TRANSACCIONES'
 ORDER BY object_type;

SELECT name, type, line, text
  FROM user_errors
 WHERE name = 'PKG_TRANSACCIONES';


-- SECCION 3: Rollback parcial paso a paso (sin procedimiento)
-- Reserva para la habitacion de menor id del 20 al 23 de enero de 2027.
-- Paso 1 crea la reserva, paso 2 marca el savepoint, paso 3 registra un pago equivocado,
-- paso 4 deshace solo el pago, paso 5 registra el pago correcto y confirma.

VARIABLE v_res NUMBER

-- Paso 1: INSERT de la reserva (cabecera + linea de habitacion)
DECLARE
  v_hab  NUMBER;
  v_aloj NUMBER;
  v_cli  NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
  SELECT id_alojamiento INTO v_aloj FROM habitacion WHERE id_habitacion = v_hab;
  SELECT MIN(id_cliente) INTO v_cli FROM cliente;

  INSERT INTO reserva (id_cliente, id_alojamiento, fecha_reserva, check_in, check_out, estado)
  VALUES (v_cli, v_aloj, TRUNC(SYSDATE), DATE '2027-01-20', DATE '2027-01-23', 'PENDIENTE')
  RETURNING id_reserva INTO :v_res;

  INSERT INTO reserva_habitacion (id_reserva, id_habitacion, id_alojamiento,
                                  check_in, check_out, huespedes, valor_estadia)
  VALUES (:v_res, v_hab, v_aloj, DATE '2027-01-20', DATE '2027-01-23', 2,
          pkg_reservas.fn_valor_estadia(v_hab, DATE '2027-01-20', DATE '2027-01-23'));

  DBMS_OUTPUT.PUT_LINE('Paso 1: reserva ' || :v_res || ' creada');
END;
/

-- Paso 2: SAVEPOINT despues de la reserva
SAVEPOINT sp_reserva_creada;

-- Paso 3: pago equivocado (se digito 9.999.999 en efectivo)
INSERT INTO pago (id_reserva, fecha_pago, monto, metodo, estado)
VALUES (:v_res, TRUNC(SYSDATE), 9999999, 'EFECTIVO', 'EXITOSO');

-- En este punto hay 1 reserva y 1 pago
SELECT (SELECT COUNT(*) FROM reserva WHERE id_reserva = :v_res) AS reservas,
       (SELECT COUNT(*) FROM pago    WHERE id_reserva = :v_res) AS pagos
  FROM dual;

-- Paso 4: ROLLBACK TO deshace solo el pago
ROLLBACK TO sp_reserva_creada;

-- La reserva sigue (1) y el pago desaparecio (0)
SELECT (SELECT COUNT(*) FROM reserva WHERE id_reserva = :v_res) AS reservas,
       (SELECT COUNT(*) FROM pago    WHERE id_reserva = :v_res) AS pagos
  FROM dual;

-- Paso 5: pago correcto (anticipo del 30 %) y COMMIT
INSERT INTO pago (id_reserva, fecha_pago, monto, metodo, estado)
SELECT :v_res, TRUNC(SYSDATE), ROUND(valor_estadia * 0.3, -3), 'PSE', 'EXITOSO'
  FROM reserva_habitacion
 WHERE id_reserva = :v_res;

UPDATE reserva SET estado = 'CONFIRMADA' WHERE id_reserva = :v_res;

COMMIT;

-- Lo que quedo guardado: la reserva confirmada con un solo pago (el correcto)
SELECT r.id_reserva, r.estado, rh.valor_estadia, p.monto, p.metodo, p.estado AS estado_pago
  FROM reserva r
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
  JOIN pago p ON p.id_reserva = r.id_reserva
 WHERE r.id_reserva = :v_res;


-- SECCION 4: Pruebas del procedimiento sp_reserva_con_pago
-- Habitacion de menor id; cliente de menor id; servicio del mismo alojamiento y uno de otro.

DECLARE
  v_hab        NUMBER;
  v_aloj       NUMBER;
  v_cli        NUMBER;
  v_serv_ok    NUMBER;
  v_serv_otro  NUMBER;
  v_res        NUMBER;
  v_pago       NUMBER;
BEGIN
  SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
  SELECT id_alojamiento INTO v_aloj FROM habitacion WHERE id_habitacion = v_hab;
  SELECT MIN(id_cliente) INTO v_cli FROM cliente;
  SELECT MIN(id_servicio) INTO v_serv_ok   FROM servicio WHERE id_alojamiento = v_aloj;
  SELECT MIN(id_servicio) INTO v_serv_otro FROM servicio WHERE id_alojamiento <> v_aloj;

  -- 4.1 Caso valido con servicio del mismo alojamiento
  pkg_transacciones.sp_reserva_con_pago(v_cli, v_hab, DATE '2027-01-24', DATE '2027-01-26', 2,
                                        200000, 'TARJETA_CREDITO', v_serv_ok, 2, v_res, v_pago);
  DBMS_OUTPUT.PUT_LINE('4.1 OK -> reserva ' || v_res || ', pago ' || v_pago);

  -- 4.2 Servicio de otro alojamiento: se descarta solo el servicio (rollback parcial),
  --     la reserva y el pago quedan
  pkg_transacciones.sp_reserva_con_pago(v_cli, v_hab, DATE '2027-01-26', DATE '2027-01-28', 2,
                                        150000, 'PSE', v_serv_otro, 1, v_res, v_pago);
  DBMS_OUTPUT.PUT_LINE('4.2 OK sin servicio -> reserva ' || v_res || ', pago ' || v_pago);

  -- 4.3 Pago mayor que el total: se deshace todo (no debe quedar reserva del 28 al 30)
  BEGIN
    pkg_transacciones.sp_reserva_con_pago(v_cli, v_hab, DATE '2027-01-28', DATE '2027-01-30', 2,
                                          999999999, 'EFECTIVO', NULL, 1, v_res, v_pago);
  EXCEPTION
    WHEN pkg_transacciones.e_pago_invalido THEN
      DBMS_OUTPUT.PUT_LINE('4.3 RECHAZADA y deshecha: ' || SQLERRM);
  END;

  -- 4.4 Metodo de pago no permitido: tambien se deshace todo
  BEGIN
    pkg_transacciones.sp_reserva_con_pago(v_cli, v_hab, DATE '2027-01-28', DATE '2027-01-30', 2,
                                          100000, 'BITCOIN', NULL, 1, v_res, v_pago);
  EXCEPTION
    WHEN pkg_transacciones.e_pago_invalido THEN
      DBMS_OUTPUT.PUT_LINE('4.4 RECHAZADA y deshecha: ' || SQLERRM);
  END;
END;
/

-- 4.5 Lo que quedo en la base: reservas del 20, 24 y 26 de enero confirmadas, cada una con su pago;
--     solo la del 24 tiene servicio; ninguna del 28 al 30
SELECT r.id_reserva, r.check_in, r.check_out, r.estado,
       (SELECT COUNT(*) FROM pago p WHERE p.id_reserva = r.id_reserva)              AS pagos,
       (SELECT COUNT(*) FROM reserva_servicio s WHERE s.id_reserva = r.id_reserva)  AS servicios
  FROM reserva r
 WHERE r.check_in >= DATE '2027-01-20' AND r.check_in < DATE '2027-02-01'
 ORDER BY r.check_in;

-- 4.6 Limpieza: se borran las reservas de prueba para dejar la base como estaba
DELETE FROM pago             WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE check_in >= DATE '2027-01-20' AND check_in < DATE '2027-02-01');
DELETE FROM reserva_servicio WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE check_in >= DATE '2027-01-20' AND check_in < DATE '2027-02-01');
DELETE FROM reserva_habitacion WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE check_in >= DATE '2027-01-20' AND check_in < DATE '2027-02-01');
DELETE FROM reserva          WHERE check_in >= DATE '2027-01-20' AND check_in < DATE '2027-02-01';
COMMIT;

SELECT COUNT(*) AS reservas_de_prueba_que_quedan
  FROM reserva
 WHERE check_in >= DATE '2027-01-20' AND check_in < DATE '2027-02-01';
