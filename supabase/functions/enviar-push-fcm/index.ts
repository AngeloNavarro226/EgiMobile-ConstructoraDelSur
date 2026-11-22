import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

function base64UrlEncode(input: Uint8Array | string): string {
  const bytes =
    typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

async function obtenerAccessTokenFcm(sa: ServiceAccount): Promise<string> {
  const ahora = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64UrlEncode(
    JSON.stringify({
      iss: sa.client_email,
      sub: sa.client_email,
      aud: "https://oauth2.googleapis.com/token",
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      iat: ahora,
      exp: ahora + 3600,
    }),
  );

  const signingInput = `${header}.${payload}`;
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );
  const assertion = `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;

  const tokenResp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!tokenResp.ok) {
    const detalle = await tokenResp.text();
    throw new Error(`Error OAuth2 Google (${tokenResp.status}): ${detalle}`);
  }
  const tokenJson = await tokenResp.json();
  return tokenJson.access_token as string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ ok: false, error: "Falta header Authorization" }),
        { status: 401, headers: CORS_HEADERS },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseServiceRoleKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) {
      return new Response(
        JSON.stringify({ ok: false, error: "JWT inválido" }),
        { status: 401, headers: CORS_HEADERS },
      );
    }

    const body = await req.json().catch(() => ({}));
    const notificacionId =
      typeof body?.notificacion_id === "string" ? body.notificacion_id : "";
    if (!notificacionId) {
      return new Response(
        JSON.stringify({ ok: false, error: "notificacion_id requerido" }),
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!saRaw) {
      return new Response(
        JSON.stringify({
          ok: false,
          omitido: true,
          motivo: "FIREBASE_SERVICE_ACCOUNT_JSON no configurado todavía",
        }),
        { status: 200, headers: CORS_HEADERS },
      );
    }

    const serviceAccount = JSON.parse(saRaw) as ServiceAccount;
    const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

    const { data: notif, error: notifError } = await admin
      .from("notificaciones")
      .select("id, obra_id, emisor_id, titulo, mensaje, es_alerta_semaforo, push_enviado")
      .eq("id", notificacionId)
      .maybeSingle();

    if (notifError || !notif) {
      return new Response(
        JSON.stringify({ ok: false, error: "Notificación no encontrada" }),
        { status: 404, headers: CORS_HEADERS },
      );
    }

    if (!notif.es_alerta_semaforo || notif.push_enviado || !notif.obra_id) {
      return new Response(
        JSON.stringify({ ok: true, omitido: true, enviados: 0 }),
        { status: 200, headers: CORS_HEADERS },
      );
    }

    // Reclamo atómico para garantizar idempotencia ante reintentos
    const { data: reclamada } = await admin
      .from("notificaciones")
      .update({ push_enviado: true })
      .eq("id", notificacionId)
      .eq("push_enviado", false)
      .select("id");

    if (!reclamada || reclamada.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, omitido: true, enviados: 0 }),
        { status: 200, headers: CORS_HEADERS },
      );
    }

    const { data: obra } = await admin
      .from("obras")
      .select("id, nombre, responsable_id, ingeniero_id")
      .eq("id", notif.obra_id)
      .maybeSingle();

    if (!obra) {
      return new Response(
        JSON.stringify({ ok: true, enviados: 0, motivo: "obra_no_encontrada" }),
        { status: 200, headers: CORS_HEADERS },
      );
    }

    // Resuelve el usuario emisor (priorizando emisor_id guardado o auth.uid())
    let emisorId: string | null = notif.emisor_id;
    let emisorRolId: string | null = null;
    if (emisorId) {
      const { data: uEmisor } = await admin
        .from("usuarios")
        .select("id, rol_id")
        .eq("id", emisorId)
        .maybeSingle();
      emisorRolId = uEmisor?.rol_id ?? null;
    } else {
      const { data: uCaller } = await admin
        .from("usuarios")
        .select("id, rol_id")
        .eq("auth_user_id", authData.user.id)
        .maybeSingle();
      emisorId = uCaller?.id ?? null;
      emisorRolId = uCaller?.rol_id ?? null;
    }

    // Dueños siempre reciben alertas de cambio de semáforo
    const { data: duenios } = await admin
      .from("usuarios")
      .select("id")
      .eq("rol_id", "rol_duenio");

    const destinatariosIds = new Set<string>(
      (duenios ?? []).map((u: { id: string }) => u.id),
    );

    if (emisorRolId === "rol_capataz") {
      // Capataz cambia semáforo -> Ingeniero a cargo + Dueño
      if (obra.ingeniero_id) {
        destinatariosIds.add(obra.ingeniero_id);
      } else {
        const { data: ingenieros } = await admin
          .from("usuarios")
          .select("id")
          .eq("rol_id", "rol_ingeniero");
        for (const ing of ingenieros ?? []) {
          destinatariosIds.add(ing.id);
        }
      }
    } else if (emisorRolId === "rol_ingeniero") {
      // Ingeniero cambia semáforo -> Capataz a cargo + Dueño
      if (obra.responsable_id) {
        destinatariosIds.add(obra.responsable_id);
      }
    } else {
      if (obra.ingeniero_id) destinatariosIds.add(obra.ingeniero_id);
      if (obra.responsable_id) destinatariosIds.add(obra.responsable_id);
    }

    if (emisorId) {
      destinatariosIds.delete(emisorId);
    }

    const idsLista = Array.from(destinatariosIds);
    if (idsLista.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, enviados: 0, destinatarios: 0 }),
        { status: 200, headers: CORS_HEADERS },
      );
    }

    const { data: usuariosDestino } = await admin
      .from("usuarios")
      .select("id, fcm_token")
      .in("id", idsLista)
      .not("fcm_token", "is", null);

    const tokens = (usuariosDestino ?? [])
      .map((u: { id: string; fcm_token: string | null }) => ({
        usuarioId: u.id,
        token: (u.fcm_token ?? "").trim(),
      }))
      .filter((item) => item.token.length > 0);

    if (tokens.length === 0) {
      return new Response(
        JSON.stringify({
          ok: true,
          enviados: 0,
          destinatarios: idsLista.length,
          motivo: "sin_tokens_fcm",
        }),
        { status: 200, headers: CORS_HEADERS },
      );
    }

    const accessToken = await obtenerAccessTokenFcm(serviceAccount);
    const fcmUrl =
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

    let enviados = 0;
    let fallidos = 0;

    for (const destino of tokens) {
      const resp = await fetch(fcmUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: destino.token,
            notification: {
              title: notif.titulo,
              body: notif.mensaje,
            },
            android: {
              priority: "HIGH",
              notification: {
                channel_id: "constructora_alertas_obras",
              },
            },
            data: {
              al_tocar: `obra:${obra.id}`,
              obra_id: obra.id,
              notificacion_id: notif.id,
            },
          },
        }),
      });

      if (resp.ok) {
        enviados++;
      } else {
        fallidos++;
        const errBody = await resp.text();
        if (errBody.includes("UNREGISTERED") || resp.status === 404) {
          await admin
            .from("usuarios")
            .update({ fcm_token: null })
            .eq("id", destino.usuarioId)
            .eq("fcm_token", destino.token);
        }
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        enviados,
        fallidos,
        destinatarios: idsLista.length,
      }),
      { status: 200, headers: CORS_HEADERS },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      }),
      { status: 500, headers: CORS_HEADERS },
    );
  }
});
