from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_list_subjects_requires_auth():
    response = client.get("/subjects/")
    assert response.status_code == 403


def test_create_subject_requires_auth():
    response = client.post("/subjects/", json={"name": "Math"})
    assert response.status_code == 403
