# rpnc
a small reverse polish notation compiler
## Building
The only dependencies are a recent (0.13.0+) Zig compiler, and the [QBE backend](https://c9x.me/compile/releases.html). The compiler looks for the `qbe-1/2` folder into the root of this project directory.
The most convenient way to build the executable is to use the `zig build-exe` command, like this:
```bash
$ zig build-exe src/rpnc.zig
```
## Usage
Provide a `.rpn` file to the `rpnc` binary, like this:
```bash
$ ./rpnc add.rpn
```
This will produce an `out` binary, the return code of which will be the final calculation when run. You can observe this in Bash like this:
```bash
$ echo $(./out)
```
or in PowerShell like this:
```powershell
> .\out.exe; $LASTEXITCODE
```