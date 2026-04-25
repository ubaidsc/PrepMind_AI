from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_signup_missing_fields():
    response = client.post("/auth/signup", json={"email": "bad"})
    assert response.status_code == 422


def test_signin_missing_fields():
    response = client.post("/auth/signin", json={})
    assert response.status_code == 422


def test_signout():
    response = client.post("/auth/signout")
    assert response.status_code == 200
    assert response.json()["message"] == "Signed out successfully"
