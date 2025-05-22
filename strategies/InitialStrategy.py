from freqtrade.strategy.interface import IStrategy
from pandas import DataFrame

class InitialStrategy(IStrategy):
    minimal_roi = {"0": 0.1}
    stoploss = -0.05
    timeframe = '5m'

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        return dataframe

    def populate_buy_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[:, 'buy'] = 0
        dataframe.loc[dataframe['close'] < dataframe['open'], 'buy'] = 1
        return dataframe

    def populate_sell_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[:, 'sell'] = 0
        dataframe.loc[dataframe['close'] > dataframe['open'], 'sell'] = 1
        return dataframe
