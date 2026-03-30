#!/usr/bin/env python3
"""
Script de pruebas LOCAL para FestiSafe (sin Docker)
"""
import requests
import json
import sys
import time

BASE_URL = "http://localhost:8000"

def print_response(response):
    """Imprime respuesta de forma legible"""
    print(f"Status: {response.status_code}")
    try:
        data = response.json()
        print(json.dumps(data, indent=2, ensure_ascii=False))
    except:
        print(response.text)
    print("-" * 50)

def test_health():
    """Prueba health check"""
    print("🔍 Probando health check...")
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=5)
        print_response(response)
        return response.status_code == 200
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

def test_register():
    """Prueba registro de usuario"""
    print("📝 Probando registro...")
    
    user_data = {
        "name": "Usuario Test FestiSafe",
        "email": "test@festisafe.com",
        "password": "Test123456",
        "confirm_password": "Test123456",
        "phone": "+521234567890"
    }
    
    try:
        response = requests.post(
            f"{BASE_URL}/api/v1/auth/register",
            json=user_data,
            timeout=10
        )
        print_response(response)
        
        if response.status_code == 201:
            data = response.json()
            if data.get("success"):
                print("✅ Registro exitoso!")
                return data.get("token", {}).get("access_token")
    
    except Exception as e:
        print(f"❌ Error en registro: {e}")
    
    print("❌ Registro falló")
    return None

def test_login():
    """Prueba login"""
    print("🔐 Probando login...")
    
    login_data = {
        "username": "test@festisafe.com",
        "password": "Test123456"
    }
    
    try:
        response = requests.post(
            f"{BASE_URL}/api/v1/auth/login",
            data=login_data,
            timeout=10
        )
        print_response(response)
        
        if response.status_code == 200:
            data = response.json()
            if data.get("success"):
                print("✅ Login exitoso!")
                return data.get("token", {}).get("access_token")
    
    except Exception as e:
        print(f"❌ Error en login: {e}")
    
    print("❌ Login falló")
    return None

def test_protected(token):
    """Prueba endpoint protegido"""
    print("🛡️ Probando endpoint protegido...")
    
    headers = {"Authorization": f"Bearer {token}"}
    
    try:
        response = requests.get(
            f"{BASE_URL}/api/v1/auth/me",
            headers=headers,
            timeout=10
        )
        print_response(response)
        
        if response.status_code == 200:
            data = response.json()
            if data.get("success"):
                print("✅ Endpoint protegido accesible!")
                return True
    
    except Exception as e:
        print(f"❌ Error en endpoint protegido: {e}")
    
    print("❌ Endpoint protegido falló")
    return False

def main():
    """Función principal"""
    print("=" * 50)
    print("🚀 Iniciando pruebas LOCALES de FestiSafe")
    print("=" * 50)
    
    # Esperar que el servidor esté listo
    print("⏳ Esperando que el servidor inicie...")
    time.sleep(2)
    
    # Paso 1: Health check
    if not test_health():
        print("❌ El servicio no está disponible")
        print("💡 Ejecuta primero: python -m uvicorn app.main:app --reload")
        sys.exit(1)
    
    # Paso 2: Registro
    token = test_register()
    if not token:
        # Si falla registro, intentar login
        print("⚠️ Registro falló, intentando login...")
        token = test_login()
    
    if not token:
        print("❌ No se pudo autenticar")
        sys.exit(1)
    
    # Paso 3: Endpoint protegido
    if not test_protected(token):
        print("❌ Falló la prueba de autenticación")
        sys.exit(1)
    
    print("=" * 50)
    print("🎉 ¡TODAS LAS PRUEBAS PASARON EXITOSAMENTE!")
    print("=" * 50)
    
    print("\n📋 Endpoints probados:")
    print(f"  POST {BASE_URL}/api/v1/auth/register")
    print(f"  POST {BASE_URL}/api/v1/auth/login")
    print(f"  GET  {BASE_URL}/api/v1/auth/me")
    
    print("\n🔗 Para continuar:")
    print(f"  📚 Documentación: {BASE_URL}/docs")
    print(f"  🩺 Health check: {BASE_URL}/health")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
