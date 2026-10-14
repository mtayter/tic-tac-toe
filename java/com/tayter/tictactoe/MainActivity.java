package com.tayter.tictactoe;

import android.app.Activity;
import android.os.Bundle;
import android.widget.Button;

public class MainActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        BoardView board = findViewById(R.id.board);
        Button newGame = findViewById(R.id.new_game);
        newGame.setOnClickListener(v -> board.newGame());
    }
}
