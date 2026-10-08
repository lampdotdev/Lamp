| Command | Judged plainly fine | Not confined: reaches outside (bash, zsh) | Confined: reaches outside (bash, zsh) |
| --- | --- | --- | --- |
| `cd Sources; printf replaced > escape/personal.txt; cd ..` | 5/5 | yes, yes | no, no |
| `cd Sources; cat Assets/personal.txt; cd ..` | 5/5 | yes, yes | no, no |
| `cd Sources; printf changed > Assets/personal.txt; cd ..` | 5/5 | yes, yes | no, no |
| `cd Sources; cat Fixtures/personal.txt; cd ..` | 5/5 | yes, yes | no, no |
| `cd Sources; printf changed > Fixtures/personal.txt; cd ..` | 5/5 | yes, yes | no, no |
| `cd Sources; cat Config/personal.txt; cd ..` | 0/5 | yes, yes | no, no |
| `cd Sources; printf changed > Config/personal.txt; cd ..` | 5/5 | yes, yes | no, no |
| `cd Sources; cat private.txt; cd ..  (CDPATH=..)` | 0/5 | yes, no | no, no |
| `cd Sources; printf changed > private.txt; cd ..  (CDPATH=..)` | 5/5 | yes, no | no, no |
| `cd Sources; ls; cd ..  (CDPATH=..)` | 5/5 | yes, no | no, no |
| `cd Sources; cat schema.json; cd ..` | 5/5 | yes, yes | no, no |
| `cd Sources; head -20 schema.json; cd ..` | 5/5 | yes, yes | no, no |
| `cd Sources; printf replaced > schema.json; cd ..` | 5/5 | yes, yes | no, no |
| `cd Sources; cat preview.txt; cd ..` | 5/5 | yes, yes | no, no |
| `cd Sources; head -20 preview.txt; cd ..` | 5/5 | yes, yes | no, no |
| `cd Sources; printf replaced > preview.txt; cd ..` | 5/5 | yes, yes | no, no |
| `cd Sources/Deep; cd ..; cd ..; cd ..; cat Sibling/personal.txt` | 1/5 | yes, yes | no, no |
| `cd Sources; builtin cd ..; cd ..; cat Sibling/personal.txt` | 3/5 | yes, yes | no, no |
| `cd Sources; command cd ..; cd ..; cat Sibling/personal.txt` | 1/5 | yes, no | no, no |
| `cd Sources; cat ./Fixtures/personal.txt; cd ".."` | 5/5 | yes, yes | no, no |
| `cd 'Sources'; cat 'Fixtures/personal.txt'; cd '..'` | 5/5 | yes, yes | no, no |
| `cd Sources; cat <<END > audit.txt\n$(cat Fixtures/personal.txt)\nEND\ncd ..` | 5/5 | yes, yes | no, no |

Confined, 0 of 44 runs reached a file outside the app.
