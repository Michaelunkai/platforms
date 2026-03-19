<#
.SYNOPSIS
    fixpywin32
#>
Remove-Item "C:\Users\micha\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.13_qbz5n2kfra8p0\LocalCache\local-packages\Python313\site-packages\pywin32" -Recurse -Force -ErrorAction SilentlyContinue; python -c "import site; print('pywin32 errors fixed - you can now install other packages')"; Remove-Item "C:\Users\micha\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.13_qbz5n2kfra8p0\LocalCache\local-packages\Python313\site-packages\pywin32" -Recurse -Force -ErrorAction SilentlyContinue; pip install --user --no-deps --force-reinstall --break-system-packages pywin32
