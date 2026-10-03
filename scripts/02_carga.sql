SET SERVEROUTPUT ON
SET DEFINE OFF


-- BLOQUE 0: Limpieza de datos
   
DELETE FROM resena;
DELETE FROM reserva_servicio;
DELETE FROM pago;
DELETE FROM reserva_habitacion;
DELETE FROM reserva;
DELETE FROM usuario_sistema;
DELETE FROM servicio;
DELETE FROM tarifa;
DELETE FROM temporada;
DELETE FROM cliente;
DELETE FROM habitacion;
DELETE FROM alojamiento;
DELETE FROM tipo_alojamiento;
DELETE FROM municipio;
COMMIT;


-- BLOQUE 1: Municipios, tipos, alojamientos y habitaciones

DECLARE
  TYPE t_vc  IS VARRAY(100) OF VARCHAR2(60);
  TYPE t_nn  IS VARRAY(100) OF NUMBER;
  TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

  -- Los 12 municipios del Quindio y cuantos alojamientos tiene cada uno
  v_muni  t_vc := t_vc('Armenia', 'Salento', 'Montenegro', 'Calarcá', 'Quimbaya',
                       'Filandia', 'Circasia', 'La Tebaida', 'Pijao', 'Córdoba',
                       'Buenavista', 'Génova');
  v_cant  t_nn := t_nn(14, 8, 8, 7, 6, 5, 4, 3, 2, 1, 1, 1);   -- suma 60

  v_tipos t_vc := t_vc('Finca cafetera', 'Hotel', 'Glamping', 'Hostal',
                       'Apartamento turístico');

  -- Palabras para nombres comerciales
  v_pal   t_vc := t_vc('Los Cafetos', 'El Yarumo', 'La Palma de Cera', 'Buenavista Verde',
    'El Guadual', 'La Esperanza', 'Monte Alegre', 'Los Naranjos', 'El Samán',
    'Vista al Cañón', 'La Aurora', 'Altos del Quindío', 'El Roble', 'Rincón Paisa',
    'La Cumbre', 'Los Nogales', 'El Diamante', 'Sol de la Montaña', 'La Pradera',
    'El Bosque', 'Aire de Montaña', 'La Colina', 'Los Helechos', 'El Cardonal',
    'Raíces Cafeteras', 'La Orquídea', 'Cielo Abierto', 'Los Guayacanes', 'El Refugio',
    'La Siembra', 'Brisa Andina', 'El Cedro', 'San Isidro', 'Las Heliconias',
    'Hacienda Vieja', 'Paraíso Verde', 'El Mirlo', 'Los Colibríes', 'La Garza',
    'Entre Cafetales', 'El Tucán', 'Nido de Cóndor', 'La Vega', 'Piedra Alta',
    'Las Camelias', 'El Arrayán', 'Cerro Bonito', 'La Ceiba', 'Los Lirios',
    'Aurora Cafetera', 'El Higuerón', 'Vientos del Eje', 'La Cascada', 'Las Palmas',
    'Tierra Linda', 'El Encanto', 'Los Balsos', 'La Pomarrosa', 'Monteverde Andino',
    'El Alba', 'Los Pinos', 'La Fortuna');

  v_tipo_id t_ids;
  v_tmp     NUMBER;
  v_mid     NUMBER;
  v_aid     NUMBER;
  v_i       PLS_INTEGER := 0;   
  v_t       PLS_INTEGER;         
  v_est     PLS_INTEGER;
  v_nh      PLS_INTEGER;
  v_pal_txt VARCHAR2(60);
  v_pref    VARCHAR2(30);
  v_nom     VARCHAR2(120);
  v_dir     VARCHAR2(160);
  v_tel     VARCHAR2(20);
  v_cor     VARCHAR2(120);
  v_mnom    VARCHAR2(60);
  v_num     VARCHAR2(10);
  v_htipo   VARCHAR2(10);
  v_cap     PLS_INTEGER;
  v_desc    VARCHAR2(300);

  FUNCTION rnd(p_lo NUMBER, p_hi NUMBER) RETURN PLS_INTEGER IS
  BEGIN
    RETURN TRUNC(DBMS_RANDOM.VALUE(p_lo, p_hi + 1));
  END;

  -- Tipo de alojamiento segun el municipio: Armenia es urbana entonces mas hoteles
  -- Salento, Quimbaya y Filandia son rurales con mas fincas y glampings
  FUNCTION pick_tipo(p_m PLS_INTEGER, p_k PLS_INTEGER) RETURN PLS_INTEGER IS
    x NUMBER := DBMS_RANDOM.VALUE(0, 100);
  BEGIN
    IF p_m = 1 AND p_k <= 5 THEN
      RETURN p_k;                       
    ELSIF p_m = 1 THEN
      IF x < 50 THEN RETURN 2; ELSIF x < 64 THEN RETURN 5;
      ELSIF x < 80 THEN RETURN 4; ELSIF x < 86 THEN RETURN 1; ELSE RETURN 3; END IF;
    ELSIF p_m IN (2, 5, 6) THEN
      IF x < 42 THEN RETURN 1; ELSIF x < 67 THEN RETURN 3;
      ELSIF x < 80 THEN RETURN 4; ELSIF x < 95 THEN RETURN 2; ELSE RETURN 5; END IF;
    ELSE
      IF x < 30 THEN RETURN 1; ELSIF x < 60 THEN RETURN 2;
      ELSIF x < 72 THEN RETURN 3; ELSIF x < 90 THEN RETURN 4; ELSE RETURN 5; END IF;
    END IF;
  END;

  -- Tipo de habitacion segun el tipo de alojamiento
  FUNCTION tipo_hab(p_t PLS_INTEGER) RETURN VARCHAR2 IS
    x NUMBER := DBMS_RANDOM.VALUE(0, 1);
  BEGIN
    IF p_t = 2 THEN                                   -- hotel
      IF x < 0.4 THEN RETURN 'SENCILLA'; ELSIF x < 0.8 THEN RETURN 'DOBLE'; ELSE RETURN 'SUITE'; END IF;
    ELSIF p_t = 1 THEN                                -- finca cafetera
      IF x < 0.8 THEN RETURN 'CABANA'; ELSE RETURN 'DOBLE'; END IF;
    ELSIF p_t = 3 THEN                                -- glamping
      IF x < 0.6 THEN RETURN 'CABANA'; ELSE RETURN 'SUITE'; END IF;
    ELSIF p_t = 4 THEN                                -- hostal
      IF x < 0.5 THEN RETURN 'SENCILLA'; ELSE RETURN 'DOBLE'; END IF;
    ELSE                                              -- apartamento turistico
      IF x < 0.6 THEN RETURN 'DOBLE'; ELSE RETURN 'SUITE'; END IF;
    END IF;
  END;

  FUNCTION cap_hab(p_tipo VARCHAR2) RETURN PLS_INTEGER IS
  BEGIN
    IF p_tipo = 'SENCILLA' THEN RETURN rnd(1, 2);
    ELSIF p_tipo = 'DOBLE' THEN RETURN rnd(2, 4);
    ELSIF p_tipo = 'SUITE' THEN RETURN rnd(3, 6);
    ELSE RETURN rnd(2, 8);
    END IF;
  END;

  FUNCTION desc_hab(p_tipo VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF p_tipo = 'SENCILLA' THEN RETURN 'Habitación sencilla con baño privado y escritorio';
    ELSIF p_tipo = 'DOBLE' THEN RETURN 'Habitación doble con baño privado y vista a la montaña';
    ELSIF p_tipo = 'SUITE' THEN RETURN 'Suite con sala de estar, baño privado y balcón';
    ELSE RETURN 'Cabaña independiente rodeada de naturaleza y cafetales';
    END IF;
  END;
BEGIN
  DBMS_RANDOM.SEED(20261001);

  -- Tipos de alojamiento
  FOR t IN 1..v_tipos.COUNT LOOP
    v_pal_txt := v_tipos(t);
    INSERT INTO tipo_alojamiento (nombre, descripcion)
    VALUES (v_pal_txt, 'Tipo de alojamiento: ' || v_pal_txt)
    RETURNING id_tipo_alojamiento INTO v_tmp;
    v_tipo_id(t) := v_tmp;
  END LOOP;

  -- Municipios, alojamientos y habitaciones
  FOR m IN 1..v_muni.COUNT LOOP
    v_mnom := v_muni(m);
    INSERT INTO municipio (nombre) VALUES (v_mnom) RETURNING id_municipio INTO v_mid;

    FOR k IN 1..v_cant(m) LOOP
      v_i := v_i + 1;
      v_t := pick_tipo(m, k);

      v_pal_txt := v_pal(1 + MOD(v_i - 1, v_pal.COUNT));
      IF v_i > v_pal.COUNT THEN v_pal_txt := v_pal_txt || ' ' || v_i; END IF;
      v_pref := CASE v_t WHEN 1 THEN 'Finca ' WHEN 2 THEN 'Hotel ' WHEN 3 THEN 'Glamping '
                         WHEN 4 THEN 'Hostal ' ELSE 'Apartamentos ' END;
      v_nom := v_pref || v_pal_txt;

      -- Estrellas autoasignadas segun el tipo
      v_est := CASE v_t WHEN 2 THEN rnd(2, 5) WHEN 1 THEN rnd(2, 4) WHEN 3 THEN rnd(3, 5)
                        WHEN 4 THEN rnd(1, 3) ELSE rnd(2, 4) END;

      IF m = 1 THEN
        v_dir := 'Carrera ' || rnd(10, 25) || ' # ' || rnd(1, 30) || '-' || rnd(1, 99);
      ELSE
        v_dir := 'Vereda ' || v_pal_txt || ', km ' || rnd(1, 15) || ' vía a ' || v_mnom;
      END IF;
      v_tmp := v_tipo_id(v_t);
      v_tel := '3' || TO_CHAR(rnd(100000000, 999999999));
      v_cor := 'reservas@' || LOWER(TRANSLATE(REPLACE(v_pal_txt, ' ', ''), 'áéíóúñ', 'aeioun'))
               || v_i || '.co';

      INSERT INTO alojamiento (nombre_comercial, direccion, estrellas, telefono, correo,
                               id_municipio, id_tipo_alojamiento)
      VALUES (v_nom, v_dir, v_est, v_tel, v_cor, v_mid, v_tmp)
      RETURNING id_alojamiento INTO v_aid;

      -- Cantidad de habitaciones: hoteles grandes en Armenia, fincas pequeñas
      IF v_t = 2 AND m = 1 THEN v_nh := rnd(30, 40);
      ELSIF v_t = 2 THEN v_nh := rnd(12, 25);
      ELSIF v_t = 1 THEN v_nh := rnd(3, 5);
      ELSIF v_t = 3 THEN v_nh := rnd(4, 9);
      ELSIF v_t = 4 THEN v_nh := rnd(8, 18);
      ELSE v_nh := rnd(5, 12);
      END IF;

      FOR r IN 1..v_nh LOOP
        IF v_t = 2 THEN
          v_num := TO_CHAR(CEIL(r / 10) * 100 + MOD(r - 1, 10) + 1);   -- 101, 102, ... 201
        ELSIF v_t = 1 THEN v_num := 'C' || r;
        ELSIF v_t = 3 THEN v_num := 'G' || r;
        ELSE v_num := TO_CHAR(100 + r);
        END IF;
        v_htipo := tipo_hab(v_t);
        v_cap   := cap_hab(v_htipo);
        v_desc  := desc_hab(v_htipo);
        INSERT INTO habitacion (id_alojamiento, numero, capacidad, tipo, descripcion)
        VALUES (v_aid, v_num, v_cap, v_htipo, v_desc);
      END LOOP;
    END LOOP;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Bloque 1 listo: ' || v_i || ' alojamientos creados.');
END;
/


-- BLOQUE 2. Temporadas 2024-2026 + enero 2027 y tarifas

DECLARE
  TYPE t_dt IS TABLE OF DATE INDEX BY PLS_INTEGER;
  v_ini t_dt;
  v_fin t_dt;
  v_prev DATE;
  v_tog  PLS_INTEGER := 0;
  c_fin_cobertura CONSTANT DATE := DATE '2027-01-31';

  FUNCTION fd(p_y NUMBER, p_md VARCHAR2) RETURN DATE IS
  BEGIN
    RETURN TO_DATE(p_y || '-' || p_md, 'YYYY-MM-DD');
  END;

  PROCEDURE ins(p_nombre VARCHAR2, p_nivel VARCHAR2, p_i DATE, p_f DATE) IS
  BEGIN
    INSERT INTO temporada (nombre, nivel, fecha_inicio, fecha_fin)
    VALUES (p_nombre, p_nivel, p_i, p_f);
  END;

  -- Intervalo entre temporadas altas: alterna MEDIA y BAJA
  PROCEDURE gap(p_i DATE, p_f DATE) IS
  BEGIN
    IF v_tog = 0 THEN
      ins('Media ' || TO_CHAR(p_i, 'YYYY-MM-DD'), 'MEDIA', p_i, p_f);
    ELSE
      ins('Baja ' || TO_CHAR(p_i, 'YYYY-MM-DD'), 'BAJA', p_i, p_f);
    END IF;
    v_tog := 1 - v_tog;
  END;
BEGIN
  -- Temporadas ALTA
  ins('Diciembre-enero 2023-2024', 'ALTA', DATE '2024-01-01', DATE '2024-01-10');
  FOR y IN 2024..2026 LOOP
    IF y = 2024 THEN
      ins('Semana Santa 2024', 'ALTA', DATE '2024-03-24', DATE '2024-03-31');
    ELSIF y = 2025 THEN
      ins('Semana Santa 2025', 'ALTA', DATE '2025-04-13', DATE '2025-04-20');
    ELSE
      ins('Semana Santa 2026', 'ALTA', DATE '2026-03-29', DATE '2026-04-05');
    END IF;
    ins('Puente de la Ascensión ' || y, 'ALTA', fd(y, '05-18'), fd(y, '05-21'));
    ins('Mitad de año ' || y,           'ALTA', fd(y, '06-15'), fd(y, '07-12'));
    ins('Puente de la Asunción ' || y,  'ALTA', fd(y, '08-15'), fd(y, '08-18'));
    ins('Puente de octubre ' || y,      'ALTA', fd(y, '10-11'), fd(y, '10-14'));
    ins('Puente de Todos los Santos ' || y,      'ALTA', fd(y, '11-01'), fd(y, '11-04'));
    ins('Puente de Independencia de Cartagena ' || y, 'ALTA', fd(y, '11-11'), fd(y, '11-14'));
    ins('Diciembre-enero ' || y || '-' || (y + 1), 'ALTA', fd(y, '12-15'), fd(y + 1, '01-10'));
  END LOOP;

  SELECT fecha_inicio, fecha_fin BULK COLLECT INTO v_ini, v_fin
    FROM temporada ORDER BY fecha_inicio;
  v_prev := DATE '2023-12-31';
  FOR i IN 1..v_ini.COUNT LOOP
    IF v_ini(i) > v_prev + 1 THEN
      gap(v_prev + 1, v_ini(i) - 1);
    END IF;
    v_prev := v_fin(i);
  END LOOP;
  IF v_prev < c_fin_cobertura THEN
    gap(v_prev + 1, c_fin_cobertura);
  END IF;
  COMMIT;
END;
/


INSERT INTO tarifa (id_habitacion, id_temporada, valor_noche)
SELECT h.id_habitacion,
       t.id_temporada,
       ROUND(
         (a.estrellas * 40000 + 30000 + ORA_HASH(a.id_alojamiento, 69) * 1000)
         * DECODE(ta.nombre, 'Finca cafetera', 1.1, 'Hotel', 1, 'Glamping', 1.5,
                             'Hostal', 0.7, 'Apartamento turístico', 1.05, 1)
         * DECODE(h.tipo, 'SENCILLA', 0.8, 'DOBLE', 1, 'SUITE', 1.6, 'CABANA', 1.3, 1)
         * DECODE(t.nivel,
                   'ALTA',  1.05 + ORA_HASH(a.id_alojamiento * 7, 65) / 100,
                   'MEDIA', 1.00 + ORA_HASH(a.id_alojamiento * 13, 15) / 100,
                            0.80 + ORA_HASH(a.id_alojamiento * 3, 10) / 100)
         * (1 + (ORA_HASH(h.id_habitacion * 1000 + t.id_temporada, 6) - 3) / 100)
       , -3)
  FROM habitacion h
  JOIN alojamiento a       ON a.id_alojamiento = h.id_alojamiento
  JOIN tipo_alojamiento ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
 CROSS JOIN temporada t;
COMMIT;


-- BLOQUE 3: Clientes (3.000) con ciudades de origen variadas

DECLARE
  TYPE t_vc IS VARRAY(60) OF VARCHAR2(40);
  v_nom t_vc := t_vc('Juan', 'María', 'Carlos', 'Luisa', 'Andrés', 'Camila', 'Santiago',
    'Valentina', 'Daniel', 'Sofía', 'Felipe', 'Laura', 'Sebastián', 'Daniela', 'Jorge',
    'Natalia', 'Mateo', 'Paula', 'Diego', 'Carolina', 'Alejandro', 'Juliana', 'Nicolás',
    'Andrea', 'Miguel', 'Mariana', 'Camilo', 'Paola', 'Esteban', 'Verónica');
    
  v_ape t_vc := t_vc('García', 'Rodríguez', 'Martínez', 'López', 'González', 'Hernández',
    'Pérez', 'Sánchez', 'Ramírez', 'Torres', 'Díaz', 'Vargas', 'Castro', 'Rojas',
    'Moreno', 'Ortiz', 'Gómez', 'Ruiz', 'Jiménez', 'Álvarez', 'Muñoz', 'Cardona',
    'Ospina', 'Londoño', 'Giraldo', 'Quintero', 'Henao', 'Salazar', 'Arias', 'Zapata');

  v_ciu t_vc := t_vc('Bogotá', 'Bogotá', 'Bogotá', 'Bogotá', 'Bogotá', 'Bogotá', 'Bogotá', 'Bogotá',
    'Medellín', 'Medellín', 'Medellín', 'Medellín', 'Medellín',
    'Cali', 'Cali', 'Cali', 'Cali',
    'Armenia', 'Armenia', 'Armenia', 'Armenia',
    'Pereira', 'Pereira', 'Pereira', 'Manizales', 'Manizales',
    'Barranquilla', 'Barranquilla', 'Bucaramanga', 'Bucaramanga',
    'Cartagena', 'Cartagena', 'Ibagué', 'Ibagué',
    'Calarcá', 'Montenegro', 'Neiva', 'Cúcuta', 'Santa Marta', 'Villavicencio',
    'Popayán', 'Pasto', 'Tuluá', 'Cartago', 'Miami', 'Madrid');
    
  v_n    VARCHAR2(40);
  v_a1   VARCHAR2(40);
  v_a2   VARCHAR2(40);
  v_ciud VARCHAR2(40);
  v_nomb VARCHAR2(120);
  v_doc  VARCHAR2(20);
  v_cor  VARCHAR2(120);
  v_tel  VARCHAR2(20);
  v_freg DATE;

  FUNCTION rnd(p_lo NUMBER, p_hi NUMBER) RETURN PLS_INTEGER IS
  BEGIN
    RETURN TRUNC(DBMS_RANDOM.VALUE(p_lo, p_hi + 1));
  END;
BEGIN
  DBMS_RANDOM.SEED(20261002);
  FOR i IN 1..3000 LOOP
    v_n    := v_nom(rnd(1, v_nom.COUNT));
    v_a1   := v_ape(rnd(1, v_ape.COUNT));
    v_a2   := v_ape(rnd(1, v_ape.COUNT));
    v_ciud := v_ciu(rnd(1, v_ciu.COUNT));
    v_nomb := v_n || ' ' || v_a1 || ' ' || v_a2;
    v_doc  := TO_CHAR(900000000 + i * 811 + rnd(0, 799));
    v_cor  := LOWER(TRANSLATE(v_n || '.' || v_a1, 'áéíóúüñÁÉÍÓÚÑ', 'aeiouunAEIOUN'))
              || i || '@ejemplo.co';
    v_tel  := '3' || TO_CHAR(rnd(100000000, 999999999));
    v_freg := DATE '2023-12-01' + rnd(0, 1000);
    INSERT INTO cliente (nombre, documento, correo, telefono, ciudad_origen, fecha_registro)
    VALUES (v_nomb, v_doc, v_cor, v_tel, v_ciud, v_freg);
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Bloque 3 listo: 3000 clientes.');
END;
/


-- BLOQUE 4. Servicios complementarios (de 4 a 7 por alojamiento)
-- El servicio pertenece a un alojamiento: el desayuno de un hotel no es el mismo registro que el desayuno de otro

DECLARE
  TYPE t_vc IS VARRAY(20) OF VARCHAR2(120);
  TYPE t_nn IS VARRAY(20) OF NUMBER;
  v_snom  t_vc := t_vc('Desayuno típico', 'Tour guiado por cafetal', 'Transporte al aeropuerto',
                       'Alquiler de bicicletas', 'Spa y masajes', 'Cena romántica',
                       'Cabalgata ecológica', 'Servicio de lavandería');
  v_sdesc t_vc := t_vc('Desayuno campesino con productos de la región',
                       'Recorrido guiado por el proceso del café con degustación',
                       'Traslado privado desde y hacia el aeropuerto El Edén',
                       'Alquiler de bicicleta por día con casco y mapa de rutas',
                       'Sesión de masajes y circuito de aguas termales',
                       'Cena para dos con menú de autor y ambientación',
                       'Cabalgata guiada de dos horas por senderos de montaña',
                       'Lavado y planchado de ropa en 24 horas');
  v_sbase t_nn  := t_nn(25000, 60000, 85000, 30000, 120000, 95000, 55000, 20000);
  v_ns    PLS_INTEGER;
  v_ini   PLS_INTEGER;
  v_idx   PLS_INTEGER;
  v_prec  NUMBER;
  v_snm   VARCHAR2(120);
  v_sds   VARCHAR2(120);
  v_total PLS_INTEGER := 0;
BEGIN
  DBMS_RANDOM.SEED(20261003);
  FOR a IN (SELECT id_alojamiento, estrellas FROM alojamiento ORDER BY id_alojamiento) LOOP
    v_ns  := TRUNC(DBMS_RANDOM.VALUE(4, 8));           
    v_ini := TRUNC(DBMS_RANDOM.VALUE(1, 9));           
    FOR j IN 1..v_ns LOOP
      v_idx  := 1 + MOD(v_ini + j - 2, 8);           
      v_snm  := v_snom(v_idx);
      v_sds  := v_sdesc(v_idx);
      -- El precio sube con las estrellas y varia +/- 10 % por alojamiento
      v_prec := ROUND(v_sbase(v_idx) * (0.7 + a.estrellas * 0.12)
                      * DBMS_RANDOM.VALUE(0.9, 1.1) / 500) * 500;
      INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio)
      VALUES (a.id_alojamiento, v_snm, v_sds, v_prec);
      v_total := v_total + 1;
    END LOOP;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Bloque 4 listo: ' || v_total || ' servicios.');
END;
/


-- BLOQUE 5: Usuarios internos, 2 administradores y 2 encargados por tipo


INSERT INTO usuario_sistema (username, nombre, correo, id_rol, id_alojamiento, activo)
VALUES ('admin01', 'Administrador Principal', 'admin01@turismouq.co', 1, NULL, 'S');
INSERT INTO usuario_sistema (username, nombre, correo, id_rol, id_alojamiento, activo)
VALUES ('admin02', 'Administrador Soporte', 'admin02@turismouq.co', 1, NULL, 'S');

INSERT INTO usuario_sistema (username, nombre, correo, id_rol, id_alojamiento, activo)
SELECT 'enc_' || LPAD(ROWNUM, 2, '0'),
       'Encargado ' || nombre_comercial,
       'encargado' || ROWNUM || '@turismouq.co',
       2,
       id_alojamiento,
       'S'
  FROM (SELECT id_alojamiento, nombre_comercial
          FROM (SELECT a.id_alojamiento, a.nombre_comercial,
                       ROW_NUMBER() OVER (PARTITION BY a.id_tipo_alojamiento
                                          ORDER BY a.id_alojamiento) AS rn
                  FROM alojamiento a)
         WHERE rn <= 2
         ORDER BY id_alojamiento);
COMMIT;


-- BLOQUE 6: Reservas, lineas de habitacion, servicios, pagos y reseñas

DECLARE
  c_total   CONSTANT PLS_INTEGER := 25000;
  c_inicio  CONSTANT DATE := DATE '2024-01-01';
  c_fin_gen CONSTANT DATE := DATE '2026-12-31';
  c_corte   CONSTANT DATE := DATE '2026-10-01';

  TYPE t_num  IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  TYPE t_map  IS TABLE OF t_num  INDEX BY PLS_INTEGER;
  TYPE t_date IS TABLE OF DATE   INDEX BY PLS_INTEGER;
  TYPE t_vc   IS VARRAY(20) OF VARCHAR2(200);

  v_hab    t_map;   -- v_hab(alojamiento)(k)  = id de la k-ésima habitación
  v_nhab   t_num;   -- v_nhab(alojamiento)    = cantidad de habitaciones
  v_cap    t_num;   -- v_cap(habitación)      = capacidad
  v_svc    t_map;   -- v_svc(alojamiento)(k)  = id del k-ésimo servicio
  v_nsvc   t_num;   -- v_nsvc(alojamiento)    = cantidad de servicios
  v_sprec  t_num;   -- v_sprec(servicio)      = precio
  v_tar    t_num;   -- v_tar(habitación*1000 + temporada) = valor por noche
  v_dtemp  t_num;   -- v_dtemp(día) = temporada de ese día (día = fecha - c_inicio)
  v_dpeso  t_num;   -- v_dpeso(día) = peso estacional del día
  v_ocup   t_num;   -- v_ocup(habitación*2000 + día) = 1 si está ocupada
  v_aid    t_num;   -- ids de alojamiento en orden
  v_cum    t_num;   -- pesos acumulados para elegir alojamiento
  v_cli    t_num;   -- ids de cliente
  v_naloj  PLS_INTEGER := 0;
  v_ncli   PLS_INTEGER := 0;
  v_cumtot NUMBER := 0;

  v_lhab t_num;  v_lin t_date;  v_lout t_date;  v_lval t_num;  v_lhue t_num;

  v_com t_vc := t_vc(
    'Mala experiencia, no lo recomiendo.', 'El servicio no estuvo a la altura.',
    'Estadía regular, con aspectos por mejorar.', 'Cumple, pero esperaba algo más.',
    'Buena atención y habitaciones limpias.', 'Lugar agradable para descansar.',
    'Excelente servicio y ubicación.', 'Muy recomendado, volveremos.',
    'Una experiencia inolvidable.', 'Todo perfecto, personal muy amable.');

  v_nres   PLS_INTEGER := 0;
  v_try    PLS_INTEGER := 0;
  v_a      PLS_INTEGER;
  v_nh     PLS_INTEGER;
  v_ci     DATE;
  v_co     DATE;
  v_noches PLS_INTEGER;
  v_ini    PLS_INTEGER;
  v_estado VARCHAR2(10);
  v_ok     BOOLEAN;
  v_h      PLS_INTEGER;
  v_li     DATE;
  v_lo     DATE;
  v_d1     PLS_INTEGER;
  v_d2     PLS_INTEGER;
  v_val    NUMBER;
  v_lead   PLS_INTEGER;
  v_fres   DATE;
  v_fcan   DATE;
  v_cliente NUMBER;
  v_id     NUMBER;
  v_x      NUMBER;
  v_est_tot NUMBER;
  v_srv_tot NUMBER;
  v_total  NUMBER;
  v_ns     PLS_INTEGER;
  v_sini   PLS_INTEGER;
  v_sid    PLS_INTEGER;
  v_cant   PLS_INTEGER;
  v_sprecio NUMBER;
  v_ant    NUMBER;
  v_fant   DATE;
  v_pagado NUMBER;
  v_calif  PLS_INTEGER;
  v_mu     NUMBER;
  v_ctxt   VARCHAR2(200);
  v_fres_d DATE;
  v_metodo VARCHAR2(20);
  v_multi  PLS_INTEGER := 0;

  FUNCTION rnd(p_lo NUMBER, p_hi NUMBER) RETURN PLS_INTEGER IS
  BEGIN
    RETURN TRUNC(DBMS_RANDOM.VALUE(p_lo, p_hi + 1));
  END;

  -- Alojamiento elegido con probabilidad proporcional a su peso, tamaño x popularidad
  FUNCTION pick_aloj RETURN PLS_INTEGER IS
    x NUMBER := DBMS_RANDOM.VALUE(0, v_cumtot);
  BEGIN
    FOR i IN 1..v_naloj LOOP
      IF x <= v_cum(i) THEN RETURN v_aid(i); END IF;
    END LOOP;
    RETURN v_aid(v_naloj);
  END;

  FUNCTION pick_start RETURN DATE IS
    d   DATE;
    off PLS_INTEGER;
    w   NUMBER;
  BEGIN
    LOOP
      d   := c_inicio + TRUNC(DBMS_RANDOM.VALUE(0, (c_fin_gen - c_inicio) + 1));
      off := d - c_inicio;
      w   := v_dpeso(off);
      w   := w * CASE EXTRACT(YEAR FROM d) WHEN 2024 THEN 0.75 WHEN 2025 THEN 0.9 ELSE 1 END;
      IF MOD(off, 7) NOT IN (4, 5) THEN w := w * 0.7; END IF;  -- viernes y sabado pesan mas
      IF DBMS_RANDOM.VALUE(0, 1) < w THEN RETURN d; END IF;
    END LOOP;
  END;

  FUNCTION pick_noches RETURN PLS_INTEGER IS
    x NUMBER := DBMS_RANDOM.VALUE(0, 100);
  BEGIN
    IF x < 20 THEN RETURN 1; ELSIF x < 50 THEN RETURN 2; ELSIF x < 75 THEN RETURN 3;
    ELSIF x < 87 THEN RETURN 4; ELSIF x < 94 THEN RETURN 5; ELSE RETURN rnd(6, 8); END IF;
  END;

  FUNCTION pick_nhab(p_max PLS_INTEGER) RETURN PLS_INTEGER IS
    x NUMBER := DBMS_RANDOM.VALUE(0, 100);
    n PLS_INTEGER;
  BEGIN
    IF x < 78 THEN n := 1; ELSIF x < 92 THEN n := 2; ELSIF x < 98 THEN n := 3; ELSE n := 4; END IF;
    RETURN LEAST(n, p_max);
  END;

  FUNCTION pick_metodo RETURN VARCHAR2 IS
    x NUMBER := DBMS_RANDOM.VALUE(0, 100);
  BEGIN
    IF x < 35 THEN RETURN 'TARJETA_CREDITO'; ELSIF x < 55 THEN RETURN 'TARJETA_DEBITO';
    ELSIF x < 75 THEN RETURN 'PSE'; ELSIF x < 92 THEN RETURN 'TRANSFERENCIA';
    ELSE RETURN 'EFECTIVO'; END IF;
  END;

  PROCEDURE reg_pago(p_res NUMBER, p_fecha DATE, p_monto NUMBER, p_estado VARCHAR2) IS
    v_met VARCHAR2(20) := pick_metodo;
  BEGIN
    INSERT INTO pago (id_reserva, fecha_pago, monto, metodo, estado)
    VALUES (p_res, p_fecha, p_monto, v_met, p_estado);
  END;
BEGIN
  DBMS_RANDOM.SEED(20261004);


  -- Repetibilidad: borrar lo generado por una ejecucion anterior de este bloque
  DELETE FROM resena;
  DELETE FROM reserva_servicio;
  DELETE FROM pago;
  DELETE FROM reserva_habitacion;
  DELETE FROM reserva;

  -- 1. Carga en memoria
  FOR r IN (SELECT id_alojamiento FROM alojamiento ORDER BY id_alojamiento) LOOP
    v_naloj := v_naloj + 1;
    v_aid(v_naloj) := r.id_alojamiento;
  END LOOP;

  FOR r IN (SELECT id_habitacion, id_alojamiento, capacidad
              FROM habitacion ORDER BY id_alojamiento, id_habitacion) LOOP
    IF NOT v_nhab.EXISTS(r.id_alojamiento) THEN v_nhab(r.id_alojamiento) := 0; END IF;
    v_nhab(r.id_alojamiento) := v_nhab(r.id_alojamiento) + 1;
    v_hab(r.id_alojamiento)(v_nhab(r.id_alojamiento)) := r.id_habitacion;
    v_cap(r.id_habitacion) := r.capacidad;
  END LOOP;

  FOR r IN (SELECT id_servicio, id_alojamiento, precio
              FROM servicio ORDER BY id_alojamiento, id_servicio) LOOP
    IF NOT v_nsvc.EXISTS(r.id_alojamiento) THEN v_nsvc(r.id_alojamiento) := 0; END IF;
    v_nsvc(r.id_alojamiento) := v_nsvc(r.id_alojamiento) + 1;
    v_svc(r.id_alojamiento)(v_nsvc(r.id_alojamiento)) := r.id_servicio;
    v_sprec(r.id_servicio) := r.precio;
  END LOOP;

  FOR r IN (SELECT id_habitacion, id_temporada, valor_noche FROM tarifa) LOOP
    v_tar(r.id_habitacion * 1000 + r.id_temporada) := r.valor_noche;
  END LOOP;

  FOR r IN (SELECT id_temporada, nivel, fecha_inicio, fecha_fin FROM temporada) LOOP
    FOR d IN 0..(r.fecha_fin - r.fecha_inicio) LOOP
      v_ini := (r.fecha_inicio - c_inicio) + d;
      v_dtemp(v_ini) := r.id_temporada;
      v_dpeso(v_ini) := CASE r.nivel WHEN 'ALTA' THEN 1 WHEN 'MEDIA' THEN 0.45 ELSE 0.2 END;
    END LOOP;
  END LOOP;

  FOR r IN (SELECT id_cliente FROM cliente ORDER BY id_cliente) LOOP
    v_ncli := v_ncli + 1;
    v_cli(v_ncli) := r.id_cliente;
  END LOOP;

  -- Peso de cada alojamiento: tamaño elevado a 0,8 por una popularidad aleatoria
  FOR i IN 1..v_naloj LOOP
    v_cumtot := v_cumtot + POWER(v_nhab(v_aid(i)), 0.8) * DBMS_RANDOM.VALUE(0.5, 2);
    v_cum(i) := v_cumtot;
  END LOOP;

  -- 2. Generacion de reservas
  WHILE v_nres < c_total LOOP
    v_try := v_try + 1;
    IF v_try > 600000 THEN
      RAISE_APPLICATION_ERROR(-20001, 'No se logró generar el volumen pedido sin solapes.');
    END IF;

    v_a      := pick_aloj;
    v_nh     := pick_nhab(v_nhab(v_a));
    v_ci     := pick_start;
    v_noches := pick_noches;
    v_co     := v_ci + v_noches;
    v_ini    := rnd(1, v_nhab(v_a));

    -- Estado segun la fecha de corte
    v_x := DBMS_RANDOM.VALUE(0, 100);
    IF v_co <= c_corte THEN
      IF v_x < 80 THEN v_estado := 'COMPLETADA'; ELSE v_estado := 'CANCELADA'; END IF;
    ELSE
      IF v_x < 62 THEN v_estado := 'CONFIRMADA';
      ELSIF v_x < 85 THEN v_estado := 'PENDIENTE';
      ELSE v_estado := 'CANCELADA'; END IF;
    END IF;

    -- Verificar disponibilidad
    v_ok := TRUE;
    FOR k IN 1..v_nh LOOP
      v_h  := v_hab(v_a)(1 + MOD(v_ini + k - 2, v_nhab(v_a)));   
      v_li := v_ci;
      v_lo := v_co;
      IF k > 1 AND v_noches >= 2 AND DBMS_RANDOM.VALUE(0, 1) < 0.15 THEN
        IF DBMS_RANDOM.VALUE(0, 1) < 0.5 THEN v_li := v_ci + 1; ELSE v_lo := v_co - 1; END IF;
      END IF;

      v_d1 := v_li - c_inicio;
      v_d2 := v_lo - c_inicio - 1;                              

      IF v_estado <> 'CANCELADA' THEN
        FOR d IN v_d1..v_d2 LOOP
          IF v_ocup.EXISTS(v_h * 2000 + d) THEN v_ok := FALSE; EXIT; END IF;
        END LOOP;
      END IF;
      EXIT WHEN NOT v_ok;

      -- Valor de la estadía noche a noche con la tarifa de la temporada vigente
      v_val := 0;
      FOR d IN v_d1..v_d2 LOOP
        v_val := v_val + v_tar(v_h * 1000 + v_dtemp(d));
      END LOOP;

      v_lhab(k) := v_h;
      v_lin(k)  := v_li;
      v_lout(k) := v_lo;
      v_lval(k) := v_val;
      v_lhue(k) := LEAST(v_cap(v_h),
                         1 + TRUNC(POWER(DBMS_RANDOM.VALUE(0, 1), 1.4) * v_cap(v_h)));
    END LOOP;
    CONTINUE WHEN NOT v_ok;

    -- Marcar ocupacion de las reservas no canceladas
    IF v_estado <> 'CANCELADA' THEN
      FOR k IN 1..v_nh LOOP
        v_d1 := v_lin(k) - c_inicio;
        v_d2 := v_lout(k) - c_inicio - 1;
        FOR d IN v_d1..v_d2 LOOP
          v_ocup(v_lhab(k) * 2000 + d) := 1;
        END LOOP;
      END LOOP;
    END IF;

    -- Fechas de la reserva: se reserva entre 1 y 120 dias antes
    v_lead := 1 + TRUNC(POWER(DBMS_RANDOM.VALUE(0, 1), 1.8) * 120);
    v_fres := LEAST(v_ci - v_lead, c_corte);
    v_fcan := NULL;
    IF v_estado = 'CANCELADA' THEN
      -- Cancela entre 0 y 30 dias antes del check-in
      v_fcan := GREATEST(v_fres, LEAST(c_corte, v_ci - TRUNC(DBMS_RANDOM.VALUE(0, 31))));
    END IF;

    -- Cliente: los de menor posicion reservan mas, clientes frecuentes
    v_cliente := v_cli(1 + TRUNC(v_ncli * POWER(DBMS_RANDOM.VALUE(0, 1), 1.7)));

    INSERT INTO reserva (id_cliente, id_alojamiento, fecha_reserva, check_in, check_out,
                         estado, fecha_cancelacion)
    VALUES (v_cliente, v_a, v_fres, v_ci, v_co, v_estado, v_fcan)
    RETURNING id_reserva INTO v_id;

    -- Lineas de habitacion
    v_est_tot := 0;
    FOR k IN 1..v_nh LOOP
      INSERT INTO reserva_habitacion (id_reserva, id_habitacion, id_alojamiento,
                                      check_in, check_out, huespedes, valor_estadia)
      VALUES (v_id, v_lhab(k), v_a, v_lin(k), v_lout(k), v_lhue(k), v_lval(k));
      v_est_tot := v_est_tot + v_lval(k);
    END LOOP;
    IF v_nh > 1 THEN v_multi := v_multi + 1; END IF;

    -- Servicios: 0 a 4 por reserva, siempre del mismo alojamiento
    v_x := DBMS_RANDOM.VALUE(0, 100);
    IF v_x < 10 THEN v_ns := 0; ELSIF v_x < 35 THEN v_ns := 1; ELSIF v_x < 65 THEN v_ns := 2;
    ELSIF v_x < 85 THEN v_ns := 3; ELSE v_ns := 4; END IF;
    v_ns := LEAST(v_ns, v_nsvc(v_a));
    v_sini := rnd(1, v_nsvc(v_a));
    v_srv_tot := 0;
    FOR j IN 1..v_ns LOOP
      v_sid := v_svc(v_a)(1 + MOD(v_sini + j - 2, v_nsvc(v_a)));
      v_x := DBMS_RANDOM.VALUE(0, 100);
      IF v_x < 55 THEN v_cant := 1; ELSIF v_x < 85 THEN v_cant := 2;
      ELSIF v_x < 95 THEN v_cant := 3; ELSE v_cant := 4; END IF;
      v_sprecio := v_sprec(v_sid);
      INSERT INTO reserva_servicio (id_reserva, id_servicio, id_alojamiento, cantidad, precio_unitario)
      VALUES (v_id, v_sid, v_a, v_cant, v_sprecio);
      v_srv_tot := v_srv_tot + v_cant * v_sprecio;
    END LOOP;

    -- Pagos: anticipo del 30 al 50 % y saldo, o pago unico
    v_total := v_est_tot + v_srv_tot;
    v_ant   := ROUND(v_total * DBMS_RANDOM.VALUE(0.3, 0.5), -3);
    IF v_ant <= 0 OR v_ant >= v_total THEN v_ant := v_total; END IF;
    v_fant  := LEAST(v_fres + rnd(0, 2), LEAST(v_ci, c_corte));

    IF v_estado = 'COMPLETADA' THEN
      IF DBMS_RANDOM.VALUE(0, 1) < 0.06 THEN
        reg_pago(v_id, v_fant, v_ant, 'FALLIDO');                 -- intento fallido previo
      END IF;
      IF v_ant >= v_total OR DBMS_RANDOM.VALUE(0, 1) < 0.55 THEN
        reg_pago(v_id, v_fant, v_total, 'EXITOSO');               -- pago único
      ELSE
        reg_pago(v_id, v_fant, v_ant, 'EXITOSO');                 -- anticipo
        reg_pago(v_id, v_ci, v_total - v_ant, 'EXITOSO');         -- saldo al llegar
      END IF;
    ELSIF v_estado = 'CONFIRMADA' THEN
      IF DBMS_RANDOM.VALUE(0, 1) < 0.5 THEN
        reg_pago(v_id, v_fant, v_total, 'EXITOSO');
      ELSE
        reg_pago(v_id, v_fant, v_ant, 'EXITOSO');                 -- saldo pendiente
      END IF;
    ELSIF v_estado = 'PENDIENTE' THEN
      IF DBMS_RANDOM.VALUE(0, 1) < 0.7 THEN
        reg_pago(v_id, v_fant, v_ant, 'PENDIENTE');
      ELSE
        reg_pago(v_id, v_fant, v_ant, 'FALLIDO');
      END IF;
    ELSE                                                           -- CANCELADA
      v_fant := LEAST(v_fant, v_fcan);
      IF DBMS_RANDOM.VALUE(0, 1) < 0.5 THEN v_pagado := v_total; ELSE v_pagado := v_ant; END IF;
      reg_pago(v_id, v_fant, v_pagado, 'EXITOSO');
      -- Regla de reembolso: mas de 5 dias de anticipacion devuelve el 80 %
      IF (v_ci - v_fcan) > 5 THEN
        reg_pago(v_id, v_fcan, ROUND(v_pagado * 0.8, 0), 'REEMBOLSADO');
      END IF;
    END IF;

    -- Reseña: cerca del 55 % de las completadas, cada alojamiento tiene su nivel de calidad
    IF v_estado = 'COMPLETADA' AND DBMS_RANDOM.VALUE(0, 1) < 0.55 THEN
      v_mu    := 3.0 + MOD(v_a * 7919, 19) / 10;                     -- promedio entre 3,0 y 4,8
      v_calif := GREATEST(1, LEAST(5, ROUND(v_mu + DBMS_RANDOM.NORMAL * 0.9)));
      v_ctxt  := NULL;
      IF DBMS_RANDOM.VALUE(0, 1) < 0.7 THEN
        v_ctxt := v_com((v_calif - 1) * 2 + rnd(1, 2));
      END IF;
      v_fres_d := LEAST(c_corte, v_co + rnd(1, 14));
      INSERT INTO resena (id_reserva, calificacion, comentario, fecha_resena)
      VALUES (v_id, v_calif, v_ctxt, v_fres_d);
    END IF;

    v_nres := v_nres + 1;
    IF MOD(v_nres, 5000) = 0 THEN
      COMMIT;
      DBMS_OUTPUT.PUT_LINE('  ... ' || v_nres || ' reservas generadas');
    END IF;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Bloque 6 listo: ' || v_nres || ' reservas (' || v_multi
                       || ' con más de una habitación) en ' || v_try || ' intentos.');
END;
/


-- BLOQUE 7: Verificacion del volumen y de la calidad de los datos

-- 7.1 Volumen frente al minimo exigido (columna cumple = SI en todas)
SELECT tabla, filas, minimo, CASE WHEN filas >= minimo THEN 'SI' ELSE 'NO' END AS cumple
  FROM (SELECT 'MUNICIPIO' AS tabla, COUNT(*) AS filas, 12 AS minimo FROM municipio
        UNION ALL SELECT 'TIPO_ALOJAMIENTO', COUNT(*), 4 FROM tipo_alojamiento
        UNION ALL SELECT 'ALOJAMIENTO', COUNT(*), 60 FROM alojamiento
        UNION ALL SELECT 'HABITACION', COUNT(*), 400 FROM habitacion
        UNION ALL SELECT 'TEMPORADA', COUNT(*), 6 FROM temporada
        UNION ALL SELECT 'TARIFA (habitación x temporada)',
                         (SELECT COUNT(*) FROM tarifa),
                         (SELECT COUNT(*) FROM habitacion) * (SELECT COUNT(*) FROM temporada)
                    FROM dual
        UNION ALL SELECT 'CLIENTE', COUNT(*), 3000 FROM cliente
        UNION ALL SELECT 'RESERVA', COUNT(*), 25000 FROM reserva
        UNION ALL SELECT 'RESERVA_HABITACION', COUNT(*), 25000 FROM reserva_habitacion
        UNION ALL SELECT 'PAGO', COUNT(*), 25000 FROM pago
        UNION ALL SELECT 'SERVICIO', COUNT(*), 30 FROM servicio
        UNION ALL SELECT 'RESERVA_SERVICIO', COUNT(*), 40000 FROM reserva_servicio
        UNION ALL SELECT 'USUARIO_SISTEMA', COUNT(*), 10 FROM usuario_sistema);

-- 7.2 Asimetria: alojamientos y habitaciones por municipio
SELECT m.nombre AS municipio,
       COUNT(DISTINCT a.id_alojamiento) AS alojamientos,
       COUNT(h.id_habitacion)           AS habitaciones
  FROM municipio m
  LEFT JOIN alojamiento a ON a.id_municipio = m.id_municipio
  LEFT JOIN habitacion h  ON h.id_alojamiento = a.id_alojamiento
 GROUP BY m.nombre
 ORDER BY alojamientos DESC, habitaciones DESC;

-- 7.3 Habitaciones por tipo de alojamiento: minimo, maximo y promedio
SELECT ta.nombre AS tipo, COUNT(*) AS alojamientos,
       MIN(x.n) AS min_hab, MAX(x.n) AS max_hab, ROUND(AVG(x.n), 1) AS prom_hab
  FROM (SELECT id_alojamiento, COUNT(*) AS n FROM habitacion GROUP BY id_alojamiento) x
  JOIN alojamiento a       ON a.id_alojamiento = x.id_alojamiento
  JOIN tipo_alojamiento ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
 GROUP BY ta.nombre
 ORDER BY max_hab DESC;

-- 7.4 Estacionalidad: reservas por nivel de la temporada del check-in
-- ALTA debe concentrar mucho mas de lo que le corresponde por dias
SELECT t.nivel,
       COUNT(*) AS reservas,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS porcentaje
  FROM reserva r
  JOIN temporada t ON r.check_in BETWEEN t.fecha_inicio AND t.fecha_fin
 GROUP BY t.nivel
 ORDER BY reservas DESC;

-- 7.5 Reservas por año y estado
SELECT EXTRACT(YEAR FROM check_in) AS anio,
       COUNT(*) AS reservas,
       SUM(CASE WHEN estado = 'COMPLETADA' THEN 1 ELSE 0 END) AS completadas,
       SUM(CASE WHEN estado = 'CONFIRMADA' THEN 1 ELSE 0 END) AS confirmadas,
       SUM(CASE WHEN estado = 'PENDIENTE'  THEN 1 ELSE 0 END) AS pendientes,
       SUM(CASE WHEN estado = 'CANCELADA'  THEN 1 ELSE 0 END) AS canceladas
  FROM reserva
 GROUP BY EXTRACT(YEAR FROM check_in)
 ORDER BY anio;

-- 7.6 Cobertura de temporadas: sin huecos ni solapes
--     dias_cubiertos debe ser igual a dias_del_periodo y solapes = 0
SELECT d.dias_cubiertos, d.dias_del_periodo, o.solapes
  FROM (SELECT SUM(fecha_fin - fecha_inicio + 1)       AS dias_cubiertos,
               MAX(fecha_fin) - MIN(fecha_inicio) + 1  AS dias_del_periodo
          FROM temporada) d
 CROSS JOIN (SELECT COUNT(*) AS solapes
               FROM temporada a JOIN temporada b
                 ON a.id_temporada < b.id_temporada
                AND a.fecha_inicio <= b.fecha_fin AND b.fecha_inicio <= a.fecha_fin) o;

-- 7.7 Reglas de negocio (los tres conteos deben ser 0)
SELECT
  -- habitación en dos reservas no canceladas con fechas cruzadas
  (SELECT COUNT(*)
     FROM reserva_habitacion a
     JOIN reserva ra ON ra.id_reserva = a.id_reserva
     JOIN reserva_habitacion b ON b.id_habitacion = a.id_habitacion
                              AND b.id_reserva_habitacion > a.id_reserva_habitacion
     JOIN reserva rb ON rb.id_reserva = b.id_reserva
    WHERE ra.estado <> 'CANCELADA' AND rb.estado <> 'CANCELADA'
      AND a.check_in < b.check_out AND b.check_in < a.check_out) AS solapes,
  -- linea con fechas fuera del rango general de la reserva
  (SELECT COUNT(*)
     FROM reserva_habitacion l JOIN reserva r ON r.id_reserva = l.id_reserva
    WHERE l.check_in < r.check_in OR l.check_out > r.check_out) AS lineas_fuera_de_rango,
  -- huespedes por encima de la capacidad
  (SELECT COUNT(*)
     FROM reserva_habitacion l JOIN habitacion h ON h.id_habitacion = l.id_habitacion
    WHERE l.huespedes > h.capacidad) AS exceso_capacidad
  FROM dual;

-- 7.8 Pagos: reservas con mas de un pago y completadas totalmente pagadas
SELECT (SELECT COUNT(*) FROM (SELECT id_reserva FROM pago GROUP BY id_reserva HAVING COUNT(*) > 1))
         AS reservas_con_varios_pagos,
       (SELECT COUNT(*) FROM (SELECT id_reserva FROM reserva_habitacion GROUP BY id_reserva HAVING COUNT(*) > 1))
         AS reservas_con_varias_habitaciones,
       (SELECT COUNT(*) FROM pago WHERE estado = 'REEMBOLSADO') AS reembolsos
  FROM dual;

-- 7.9 Reseñas: porcentaje sobre completadas minimo 40 % y promedio por rango
SELECT (SELECT COUNT(*) FROM resena) AS resenas,
       (SELECT COUNT(*) FROM reserva WHERE estado = 'COMPLETADA') AS completadas,
       ROUND(100 * (SELECT COUNT(*) FROM resena)
             / NULLIF((SELECT COUNT(*) FROM reserva WHERE estado = 'COMPLETADA'), 0), 1) AS porcentaje,
       (SELECT ROUND(MIN(prom), 2) FROM (SELECT AVG(rs.calificacion) AS prom
          FROM resena rs JOIN reserva r ON r.id_reserva = rs.id_reserva
         GROUP BY r.id_alojamiento)) AS prom_minimo_por_alojamiento,
       (SELECT ROUND(MAX(prom), 2) FROM (SELECT AVG(rs.calificacion) AS prom
          FROM resena rs JOIN reserva r ON r.id_reserva = rs.id_reserva
         GROUP BY r.id_alojamiento)) AS prom_maximo_por_alojamiento
  FROM dual;
