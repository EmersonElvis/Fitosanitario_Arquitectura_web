"""Recomendaciones de manejo mostradas al agricultor.

IMPORTANTE: son medidas generales de manejo integrado (cultural y de monitoreo). No incluyen
productos ni dosis. Antes de usar la aplicación con agricultores reales deben ser revisadas y
aprobadas por un ingeniero agrónomo o contrastadas con las guías oficiales de SENASA o INIA.
"""

AVISO = (
    "Este resultado es una orientación y no reemplaza la visita de un técnico agrícola. "
    "Ante dudas, consulte a un ingeniero agrónomo o al SENASA antes de aplicar cualquier producto."
)

RECOMENDACIONES: dict[str, list[str]] = {
    "hoja_sana": [
        "La hoja no muestra señales claras de enfermedad. Siga revisando sus plantas cada pocos días.",
        "Revise con más atención después de lluvias, neblina o varios días húmedos y frescos.",
        "No aplique fungicidas sin necesidad: gastará dinero y puede dañar el ambiente.",
        "Use semilla sana y rote el cultivo para mantener la parcela protegida.",
    ],
    "tizon_tardio": [
        "Posible tizón tardío (rancha). Es una enfermedad que avanza rápido con humedad y frío: actúe pronto.",
        "Recorra toda la parcela y marque las plantas afectadas para vigilar si la mancha se extiende.",
        "Retire con cuidado las hojas o plantas muy afectadas, colóquelas en una bolsa y sáquelas del campo. No las deje en el suelo.",
        "Evite regar de forma que el follaje quede mojado durante la noche y mejore la ventilación entre plantas.",
        "Consulte cuanto antes a un técnico agrícola o al SENASA sobre los productos autorizados y el momento de aplicación.",
        "Elimine papas que hayan brotado solas fuera de temporada: pueden mantener la enfermedad.",
    ],
    "tizon_temprano": [
        "Posible tizón temprano. Suele afectar más a las plantas debilitadas o con falta de nutrientes o de agua.",
        "Revise si las manchas tienen anillos como una diana y si las hojas de abajo se amarillean primero.",
        "Retire los restos de plantas enfermas de la cosecha anterior y no los deje en el terreno.",
        "Cuide la fertilización y el riego para que la planta no sufra estrés.",
        "Rote con cultivos que no sean papa, tomate ni otras solanáceas, y use semilla sana.",
        "Consulte a un técnico agrícola o al SENASA para confirmar el diagnóstico y definir el tratamiento adecuado.",
    ],
}

RECOMENDACIONES_POCO_CONCLUYENTE = [
    "El sistema no está seguro del resultado. No tome decisiones solo con esta foto.",
    "Tome otra foto con luz natural, de una sola hoja, bien enfocada y sin sombras fuertes.",
    "Coloque la hoja sobre un fondo liso y acérquese lo suficiente para ver las manchas.",
    "Si las manchas continúan o crecen, consulte a un técnico agrícola.",
]


def obtener_recomendaciones(clase: str, poco_concluyente: bool) -> list[str]:
    if poco_concluyente:
        return list(RECOMENDACIONES_POCO_CONCLUYENTE)
    return list(RECOMENDACIONES[clase])
