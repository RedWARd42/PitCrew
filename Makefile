mock:
	python -m uvicorn backend.mock_server:app --port 8000
backend:
	python -m uvicorn backend.app:app --port 8000
inject:
	python scripts/inject.py $(S)
check:
	python -m pytest -q contracts backend
	flutter test
