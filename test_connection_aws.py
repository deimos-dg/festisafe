#!/usr/bin/env python3
"""
Pruebas de conexión contra el backend FestiSafe desplegado en AWS.

Uso:
    python test_connection_aws.py

Requiere: pip install requests
"""
import json
import sys
import time
import uuid

import requests

BASE_URL = "https://festisafe-alb-814303465.us-east-1.elb.amazonaws.com"
TIMEOUT = 15

# Email único por ejecución para evitar conflictos de unicidad
_RUN_ID = uuid.uuid4().hex[:8]
TEST_EMAIL = f"test_{_RUN_ID}@festisafe-test.com"
TEST_PASSWORD = "TestPass1!secure"
TEST_NAME = "Test AWS Connection"


def _print(label: str, response: requests.Response) -> None:
    status = response.status_code
    icon = "✅" if status < 400 else "❌"
    print(f"{icon} [{status}] {label}")
    try:
        print(json.dumps(response.json(), indent=2, ensure_ascii=False))
    except Exception:
        print(response.text[:500])
    print("-" * 60)


def test_health() -> bool:
    print("🔍 Health check...")
    try:
        r = requests.get(f"{BASE_URL}/health/", timeout=TIMEOUT)
        _print("GET /health/", r)
        if r.status_code == 200:
            data = r.json()
            assert data.get("status") == "ok", f"status inesperado: {data}"
            print(f"   Versión: {data.get('version', 'N/A')}")
            return True
    except Exception as e:
        print(f"❌ Error: {e}")
    return False


def test_register() -> bool:
    print(f"\n📝 Registro ({TEST_EMAIL})...")
    try:
        r = requests.post(
            f"{BASE_URL}/api/v1/auth/register",
            json={
                "name": TEST_NAME,
                "email": TEST_EMAIL,
                "password": TEST_PASSWORD,
                "confirm_password": TEST_PASSWORD,
            },
            timeout=TIMEOUT,
        )
        _print("POST /api/v1/auth/register", r)
        return r.status_code in (200, 201)
    except Exception as e:
        print(f"❌ Error: {e}")
    return False


def test_login() -> str | None:
    print(f"\n🔐 Login ({TEST_EMAIL})...")
    try:
        r = requests.post(
            f"{BASE_URL}/api/v1/auth/login",
            json={"email": TEST_EMAIL, "password": TEST_PASSWORD},
            timeout=TIMEOUT,
        )
        _print("POST /api/v1/auth/login", r)
        if r.status_code == 200:
            data = r.json()
            token = data.get("access_token")
            if token:
                print(f"   Token obtenido: {token[:20]}...")
                return token
    except Exception as e:
        print(f"❌ Error: {e}")
    return None


def test_profile(token: str) -> bool:
    print("\n👤 Perfil autenticado...")
    try:
        r = requests.get(
            f"{BASE_URL}/api/v1/users/me",
            headers={"Authorization": f"Bearer {token}"},
            timeout=TIMEOUT,
        )
        _print("GET /api/v1/users/me", r)
        return r.status_code == 200
    except Exception as e:
        print(f"❌ Error: {e}")
    return False


def test_forgot_password() -> bool:
    print("\n📧 Forgot password (anti-enumeración)...")
    try:
        # Email existente — debe devolver 200 (respuesta genérica)
        r = requests.post(
            f"{BASE_URL}/api/v1/auth/forgot-password",
            json={"email": TEST_EMAIL},
            timeout=TIMEOUT,
        )
        _print("POST /api/v1/auth/forgot-password (email existente)", r)
        if r.status_code != 200:
            return False

        # Email inexistente — también debe devolver 200 (anti-enumeración)
        r2 = requests.post(
            f"{BASE_URL}/api/v1/auth/forgot-password",
            json={"email": f"noexiste_{_RUN_ID}@nowhere.com"},
            timeout=TIMEOUT,
        )
        _print("POST /api/v1/auth/forgot-password (email inexistente)", r2)
        if r2.status_code != 200:
            print("❌ Anti-enumeración fallida: email inexistente devolvió código distinto")
            return False

        print("   ✅ Anti-enumeración correcta: ambos emails devuelven 200")
        return True
    except Exception as e:
        print(f"❌ Error: {e}")
    return False


def test_reset_password_invalid_token() -> bool:
    print("\n🔑 Reset password con token inválido (debe devolver 400)...")
    try:
        r = requests.post(
            f"{BASE_URL}/api/v1/auth/reset-password",
            json={
                "token": "a" * 64,  # token de 64 chars que no existe en BD
                "new_password": "NewPass1!secure",
                "confirm_password": "NewPass1!secure",
            },
            timeout=TIMEOUT,
        )
        _print("POST /api/v1/auth/reset-password (token inválido)", r)
        if r.status_code == 400:
            print("   ✅ Token inválido rechazado correctamente con 400")
            return True
        print(f"   ❌ Se esperaba 400, se obtuvo {r.status_code}")
    except Exception as e:
        print(f"❌ Error: {e}")
    return False


def test_change_password_unauthenticated() -> bool:
    print("\n🔒 Change password sin JWT (debe devolver 401)...")
    try:
        r = requests.post(
            f"{BASE_URL}/api/v1/auth/change-password",
            json={
                "current_password": "OldPass1!secure",
                "new_password": "NewPass1!secure",
                "confirm_password": "NewPass1!secure",
            },
            timeout=TIMEOUT,
        )
        _print("POST /api/v1/auth/change-password (sin JWT)", r)
        if r.status_code == 401:
            print("   ✅ Sin JWT rechazado correctamente con 401")
            return True
        print(f"   ❌ Se esperaba 401, se obtuvo {r.status_code}")
    except Exception as e:
        print(f"❌ Error: {e}")
    return False


def main() -> int:
    print("=" * 60)
    print("🚀 FestiSafe — Pruebas de conexión AWS")
    print(f"   Backend: {BASE_URL}")
    print("=" * 60)

    results: dict[str, bool] = {}

    results["health"] = test_health()
    if not results["health"]:
        print("\n❌ El backend no está disponible. Abortando.")
        return 1

    results["register"] = test_register()
    if results["register"]:
        time.sleep(0.5)  # pequeña pausa para evitar rate limit
        token = test_login()
        results["login"] = token is not None
        if token:
            results["profile"] = test_profile(token)
        else:
            results["profile"] = False
    else:
        results["login"] = False
        results["profile"] = False

    results["forgot_password"] = test_forgot_password()
    results["reset_invalid_token"] = test_reset_password_invalid_token()
    results["change_unauthenticated"] = test_change_password_unauthenticated()

    # Resumen
    print("\n" + "=" * 60)
    print("📋 Resumen")
    print("=" * 60)
    all_passed = True
    for name, passed in results.items():
        icon = "✅" if passed else "❌"
        print(f"  {icon} {name}")
        if not passed:
            all_passed = False

    print()
    if all_passed:
        print("🎉 Todas las pruebas pasaron.")
    else:
        print("⚠️  Algunas pruebas fallaron. Revisa los logs anteriores.")

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
