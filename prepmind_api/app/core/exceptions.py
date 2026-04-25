from fastapi import HTTPException, status
from typing import Any


class AppException(Exception):
    def __init__(self, status_code: int, message: str, detail: Any = None):
        self.status_code = status_code
        self.message = message
        self.detail = detail
        super().__init__(message)


class NotFoundError(AppException):
    def __init__(self, resource: str = "Resource"):
        super().__init__(
            status_code=status.HTTP_404_NOT_FOUND,
            message=f"{resource} not found",
        )


class ForbiddenError(AppException):
    def __init__(self, message: str = "Access denied"):
        super().__init__(
            status_code=status.HTTP_403_FORBIDDEN,
            message=message,
        )
